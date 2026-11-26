/**
 * Bot brains: turn an Observation into a Decision. Slow and async (about every
 * 1.5 s per bot); the Bot controller carries the decision out at 10 Hz.
 */
import type { Logger } from "../log.js";
import type { Decision, EnemyObs, Mode, Observation } from "./botLogic.js";

export type { Decision, Mode, Observation } from "./botLogic.js";

export interface Brain {
  decide(o: Observation, signal: AbortSignal): Promise<Decision>;
}

const MAX_HP = 100;
/** A mining planet farther than this is not worth the trip. */
const MINE_MAX_PX = 4000;

/** Rule-based brain. Also the fallback of JevBrain. */
export class HeuristicBrain implements Brain {
  decide(o: Observation, _signal?: AbortSignal): Promise<Decision> {
    return Promise.resolve(this.decideSync(o));
  }

  decideSync(o: Observation): Decision {
    const { self, enemies, loot, threat, rocks, planet } = o;
    const hpRatio = self.hp / MAX_HP;
    const aggression = clamp01(0.3 + 0.5 * hpRatio);
    const nearest = enemies[0] ?? null; // sorted by distance

    // Hurt and somebody close (or being shot at): run
    if (self.hp < 35 && ((nearest && nearest.distance < 1200) || threat.incomingBullets > 0)) {
      return { mode: "flee", targetId: null, aggression: 0.1 };
    }
    const danger = enemies.some((e) => e.distance < 800 && (e.approaching || self.pvp));
    const lootNear = loot[0] && loot[0].distance < (self.pvp ? 1500 : 6000);

    // Retaliate against whoever shot us recently (while healthy enough)
    if (self.pvp && self.recentlyAttackedBy !== null && hpRatio > 0.4) {
      const attacker = enemies.find((e) => e.slot === self.recentlyAttackedBy);
      if (attacker) return { mode: "attack", targetId: attacker.id, aggression };
    }
    if (lootNear && !danger) return { mode: "collect", targetId: null, aggression };

    if (self.pvp && self.canInitiateFights) {
      const weaker = enemies.find((e) => e.distance < 1200 && e.hp <= self.hp);
      if (weaker) return { mode: "attack", targetId: weaker.id, aggression };
      const leader = enemies.find((e) => e.isLeader && e.distance < 3000);
      if (leader && hpRatio > 0.6) {
        return { mode: "hunt_leader", targetId: leader.id, aggression };
      }
    }
    // Economy: mine a planet or farm rocks while the hold has room
    if (self.holdFree > 0) {
      const canMine = planet !== null && planet.distance < MINE_MAX_PX;
      const canFarm = rocks.count > 0;
      if (canMine && (self.preferMining || !canFarm)) return { mode: "mine", targetId: null, aggression: 0.3 };
      if (canFarm) return { mode: "farm", targetId: null, aggression: 0.3 };
    }
    return { mode: "roam", targetId: null, aggression: 0.5 };
  }
}

// ---- Jev (Vercel AI Gateway decision model) ---------------------------------

/** Loose shape of `experimental_decide` (so tests can inject a fake). */
export type DecideFn = (opts: {
  model: string;
  state: Record<string, unknown>;
  questions: Record<string, unknown>;
  abortSignal?: AbortSignal;
  maxRetries?: number;
}) => Promise<{ answers: Record<string, any> }>;

/** Loads the AI SDK only when a Jev brain actually decides. */
const defaultDecide: DecideFn = async (opts) => {
  const { experimental_decide } = await import("ai");
  return (await experimental_decide(opts as any)) as any;
};

export interface JevBrainOptions {
  model: string;
  decide?: DecideFn;
  fallback?: HeuristicBrain;
  timeoutMs?: number;
  /** Consecutive failures that open the circuit breaker. */
  failureLimit?: number;
  breakerMs?: number;
  now?: () => number;
  log?: Logger;
}

const NEAR_ENEMY_PX = 3000;
const NEAR_LOOT_PX = 2500;
const NEAR_PLANET_PX = 4000;

const MODE_CRITERIA: Record<Mode, string> = {
  attack: "Engage the chosen target: keep 350-600 px away, strafe and shoot. Needs pvp on and a target.",
  hunt_leader: "Attack the ranking leader (the enemy with the most minerals) to steal their score.",
  flee: "Run away from nearby enemies and bullets. Use when hurt or outgunned.",
  collect: "Fly to the nearest valuable mineral orb and pick it up to raise the score.",
  farm: "Shoot the nearest asteroid from 300-500 px; broken rocks drop mineral orbs. Safe income.",
  mine: "Fly to the nearest mining planet and orbit inside its gravity range to mine minerals slowly and safely.",
  roam: "Wander the safe area looking for action. Use when nothing is close.",
};

export class JevBrain implements Brain {
  private readonly decideFn: DecideFn;
  private readonly fallback: HeuristicBrain;
  private readonly timeoutMs: number;
  private readonly failureLimit: number;
  private readonly breakerMs: number;
  private readonly now: () => number;
  private failures = 0;
  private openUntil = 0;

  constructor(private readonly opts: JevBrainOptions) {
    this.decideFn = opts.decide ?? defaultDecide;
    this.fallback = opts.fallback ?? new HeuristicBrain();
    this.timeoutMs = opts.timeoutMs ?? 1200;
    this.failureLimit = opts.failureLimit ?? 3;
    this.breakerMs = opts.breakerMs ?? 60_000;
    this.now = opts.now ?? Date.now;
  }

  get breakerOpen(): boolean {
    return this.now() < this.openUntil;
  }

  async decide(o: Observation, signal: AbortSignal): Promise<Decision> {
    const fallback = this.fallback.decideSync(o);
    const nearEnemy = o.enemies.some((e) => e.distance <= NEAR_ENEMY_PX);
    const nearLoot = o.loot.some((l) => l.distance <= NEAR_LOOT_PX);
    const nearEconomy = o.rocks.count > 0 || (o.planet !== null && o.planet.distance <= NEAR_PLANET_PX);
    if (!nearEnemy && !nearLoot && !nearEconomy && o.threat.incomingBullets === 0) {
      return { mode: "roam", targetId: null, aggression: 0.5 };
    }
    if (this.breakerOpen) return fallback;

    try {
      const answers = await this.ask(o, signal);
      this.failures = 0;
      return this.map(o, answers, fallback);
    } catch (err) {
      this.fail(err);
      return fallback;
    }
  }

  private fail(err: unknown): void {
    this.failures++;
    this.opts.log?.("jev_error", {
      message: err instanceof Error ? err.message : String(err),
      failures: this.failures,
    });
    if (this.failures >= this.failureLimit) {
      this.openUntil = this.now() + this.breakerMs;
      this.failures = 0;
      this.opts.log?.("jev_circuit_open", { ms: this.breakerMs });
    }
  }

  private async ask(o: Observation, signal: AbortSignal): Promise<Record<string, any>> {
    const modes = this.allowedModes(o);
    const questions: Record<string, unknown> = {
      mode: {
        type: "choice",
        instructions:
          "You pilot a ship in a space battle royale. Pick the best strategy for the next second or two. " +
          "Score = minerals carried; dying drops 60% of them as orbs anyone can grab. " +
          "Prefer farming and mining; fight only when provoked or clearly winning.",
        criteria: Object.fromEntries(modes.map((m) => [m, MODE_CRITERIA[m]])),
      },
      aggression: {
        type: "score",
        instructions: "How aggressively should the ship play right now?",
        criteria: ["cautious", "balanced", "reckless"],
      },
    };
    if (o.enemies.length > 0) {
      questions.target = {
        type: "choice",
        instructions: "Which enemy is the best target (or to watch), considering distance, hp and score?",
        criteria: {
          ...Object.fromEntries(o.enemies.map((e) => [`e${e.slot}`, describe(e)])),
          none: "No enemy is worth targeting.",
        },
      };
    }
    // Enemy ids stay server-side: the model only sees the slots e0..e3
    const state = {
      ...o,
      enemies: o.enemies.map(({ id: _id, slot, ...rest }) => ({ slot: `e${slot}`, ...rest })),
    };

    const abort = new AbortController();
    const onAbort = () => abort.abort(signal.reason);
    if (signal.aborted) abort.abort(signal.reason);
    else signal.addEventListener("abort", onAbort, { once: true });
    let timer: NodeJS.Timeout | undefined;
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(() => {
        const err = new Error(`jev timeout after ${this.timeoutMs}ms`);
        abort.abort(err);
        reject(err);
      }, this.timeoutMs);
    });
    try {
      const result = await Promise.race([
        this.decideFn({
          model: this.opts.model,
          state,
          questions,
          abortSignal: abort.signal,
          maxRetries: 0,
        }),
        timeout,
      ]);
      return result.answers;
    } finally {
      clearTimeout(timer);
      signal.removeEventListener("abort", onAbort);
    }
  }

  private allowedModes(o: Observation): Mode[] {
    const modes: Mode[] = ["flee", "roam"];
    if (o.loot.length > 0) modes.push("collect");
    if (o.rocks.count > 0) modes.push("farm");
    if (o.planet !== null) modes.push("mine");
    const targets = this.attackable(o);
    if (targets.length > 0) {
      modes.push("attack");
      if (targets.some((e) => e.isLeader)) modes.push("hunt_leader");
    }
    return modes;
  }

  /** Enemies that may be attacked: anyone for sharp bots, else only who shot us. */
  private attackable(o: Observation): EnemyObs[] {
    if (!o.self.pvp) return [];
    if (o.self.canInitiateFights) return o.enemies;
    return o.enemies.filter((e) => e.slot === o.self.recentlyAttackedBy);
  }

  /** Validates the model's answers against what is possible; bad fields use the heuristic's. */
  private map(o: Observation, answers: Record<string, any>, fb: Decision): Decision {
    const allowed = this.allowedModes(o);
    const rawMode = answers.mode?.choice;
    const mode: Mode = allowed.includes(rawMode) ? rawMode : fb.mode;

    const score = answers.aggression?.score;
    const aggression = typeof score === "number" && Number.isFinite(score) ? clamp01(score / 2) : fb.aggression;

    let targetId: string | null = null;
    const rawTarget = answers.target?.choice;
    if (typeof rawTarget === "string") {
      const enemy = o.enemies.find((e) => `e${e.slot}` === rawTarget);
      if (enemy) targetId = enemy.id;
    }
    const targets = this.attackable(o);
    if (mode === "hunt_leader") targetId = targets.find((e) => e.isLeader)?.id ?? targetId;
    if (mode === "attack" && !targets.some((e) => e.id === targetId)) {
      targetId = fb.mode === "attack" ? fb.targetId : (targets[0]?.id ?? null);
    }
    if ((mode === "attack" || mode === "hunt_leader") && targetId === null) return fb;
    return { mode, targetId, aggression };
  }
}

function describe(e: EnemyObs): string {
  return (
    `${e.name}: ${e.distance} px away, hp ${e.hp}, score ${e.score}` +
    (e.isLeader ? ", ranking leader" : "") +
    (e.approaching ? ", approaching" : "")
  );
}

function clamp01(n: number): number {
  return Math.max(0, Math.min(1, n));
}

export type BrainKind = "auto" | "jev" | "heuristic";

/** Builds the brain named by the config; `auto` uses Jev only when a gateway key is set. */
export function createBrain(
  kind: BrainKind,
  model: string,
  log?: Logger,
  env: NodeJS.ProcessEnv = process.env,
): Brain {
  const useJev = kind === "jev" || (kind === "auto" && !!env.AI_GATEWAY_API_KEY);
  if (kind === "jev" && !env.AI_GATEWAY_API_KEY) {
    log?.("bot_brain_warning", { message: "BOT_BRAIN=jev but AI_GATEWAY_API_KEY is not set; calls will fall back" });
  }
  return useJev ? new JevBrain({ model, log }) : new HeuristicBrain();
}
