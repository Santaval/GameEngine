/**
 * Runs the in-process bots: keeps humans + bots at the configured total and
 * drives each bot (10 Hz controller + slow async brain).
 */
import type { Logger } from "../log.js";
import type { PlayerId } from "../protocol.js";
import { Bot, type Incoming, type Mode, type Outgoing } from "./botLogic.js";
import type { Brain, Decision } from "./brain.js";

/** What the manager needs from the server. */
export interface BotHost {
  /** Humans (non-bot members) currently in the room. */
  humanCount(): number;
  /** Joins a virtual client. `deliver` receives its incoming messages. */
  join(name: string, deliver: (msg: Incoming) => void): { id: PlayerId; route(msg: Outgoing): void };
  leave(id: PlayerId): void;
}

export interface BotManagerOptions {
  /** Fill the room up to this many ships. */
  bots: number;
  decisionMs: number;
  /** Delay between adding/removing one bot and the next. */
  stepMs?: number;
  /** Bot difficulty 0..1 (default DEFAULT_SKILL). */
  skill?: number;
  debug?: boolean;
  rng?: () => number;
}

const NAMES = ["Vega", "Orion", "Lyra", "Altair", "Rigel", "Sirius", "Draco", "Nova", "Cygnus", "Pulsar", "Antares", "Hydra"];

/** Farm, mine and roam decisions are kept at least this long unless something urgent fires. */
export const HOLD_DECISION_MS = 4000;
const CALM_MODES: ReadonlySet<Mode> = new Set<Mode>(["farm", "mine", "roam"]);

/** Drives one Bot: ticks the controller and asks the brain on a jittered timer. */
export class BotDriver {
  private nextDecisionAt = 0;
  private inFlight: AbortController | null = null;
  private calmSince = -Infinity;

  constructor(
    readonly bot: Bot,
    private readonly brain: Brain,
    private readonly decisionMs: number,
    private readonly rng: () => number = Math.random,
  ) {}

  tick(dtSec: number, nowMs: number): void {
    this.bot.tick(dtSec);
    if (this.inFlight || nowMs < this.nextDecisionAt) return;
    if (this.bot.playerId === null || this.bot.dead) return;
    const ac = new AbortController();
    this.inFlight = ac;
    this.brain
      .decide(this.bot.observe(), ac.signal)
      .then((d) => {
        if (!ac.signal.aborted) this.apply(d);
      })
      .catch(() => {})
      .finally(() => {
        this.inFlight = null;
        this.nextDecisionAt = Date.now() + this.decisionMs * (0.8 + 0.4 * this.rng());
      });
  }

  /** Hysteresis: do not flip between calm modes more often than HOLD_DECISION_MS. */
  private apply(d: Decision): void {
    const now = Date.now();
    const cur = this.bot.decision.mode;
    if (CALM_MODES.has(cur) && CALM_MODES.has(d.mode) && d.mode !== cur && now - this.calmSince < HOLD_DECISION_MS) {
      return;
    }
    if (d.mode !== cur) this.calmSince = now;
    this.bot.setDecision(d);
  }

  stop(): void {
    this.inFlight?.abort();
  }
}

export class BotManager {
  private readonly drivers = new Map<PlayerId, { driver: BotDriver; name: string }>();
  private readonly timer: NodeJS.Timeout;
  private stepTimer: NodeJS.Timeout | null = null;
  private lastTick = Date.now();
  private stopped = false;
  private readonly stepMs: number;
  private readonly rng: () => number;

  constructor(
    private readonly host: BotHost,
    private readonly brain: Brain,
    private readonly opts: BotManagerOptions,
    private readonly log: Logger,
  ) {
    this.stepMs = opts.stepMs ?? 250;
    this.rng = opts.rng ?? Math.random;
    this.timer = setInterval(() => this.tick(), 100);
  }

  get count(): number {
    return this.drivers.size;
  }

  private desired(): number {
    const humans = this.host.humanCount();
    return humans > 0 ? Math.max(0, this.opts.bots - humans) : 0;
  }

  /** Call after every human join/leave. Adds or removes one bot per step. */
  reconcile(): void {
    if (this.stopped || this.stepTimer || this.drivers.size === this.desired()) return;
    this.stepTimer = setTimeout(() => {
      this.stepTimer = null;
      this.step();
      this.reconcile();
    }, this.stepMs);
  }

  private step(): void {
    const want = this.desired();
    if (this.drivers.size < want) this.addBot();
    else if (this.drivers.size > want) {
      const newest = [...this.drivers.keys()].pop() as PlayerId;
      this.removeBot(newest);
    }
  }

  private pickName(): string {
    const used = new Set([...this.drivers.values()].map((d) => d.name));
    for (let n = 0; ; n++) {
      for (const base of NAMES) {
        const name = `BOT ${base}${n ? ` ${n + 1}` : ""}`;
        if (!used.has(name)) return name;
      }
    }
  }

  private addBot(): void {
    const name = this.pickName();
    let route: (m: Outgoing) => void = () => {};
    const bot = new Bot({
      name,
      host: false,
      pvp: false,
      skill: this.opts.skill,
      rng: this.rng,
      now: () => Date.now(),
      send: (m) => route(m),
      log: this.opts.debug ? (line) => this.log("bot", { name, line }) : undefined,
    });
    const conn = this.host.join(name, (msg) => bot.onMessage(msg));
    route = conn.route;
    this.drivers.set(conn.id, { driver: new BotDriver(bot, this.brain, this.opts.decisionMs, this.rng), name });
    this.log("bot_added", { playerId: conn.id, name, bots: this.drivers.size });
  }

  private removeBot(id: PlayerId): void {
    const entry = this.drivers.get(id);
    if (!entry) return;
    entry.driver.stop();
    this.drivers.delete(id);
    this.host.leave(id);
    this.log("bot_removed", { playerId: id, name: entry.name, bots: this.drivers.size });
  }

  private tick(): void {
    const now = Date.now();
    const dt = Math.min(0.25, (now - this.lastTick) / 1000);
    this.lastTick = now;
    for (const { driver } of this.drivers.values()) {
      try {
        driver.tick(dt, now);
      } catch (err) {
        this.log("bot_error", { message: err instanceof Error ? err.message : String(err) });
      }
    }
  }

  stop(): void {
    this.stopped = true;
    clearInterval(this.timer);
    if (this.stepTimer) clearTimeout(this.stepTimer);
    for (const { driver } of this.drivers.values()) driver.stop();
    this.drivers.clear();
  }
}
