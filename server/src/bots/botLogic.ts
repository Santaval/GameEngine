/**
 * Pure bot logic (Aval Cup player). No sockets, no clock, no `ai` import: the
 * caller feeds it incoming messages (`onMessage`), time steps (`tick`) and
 * receives outgoing messages through `send`.
 *
 * Two layers: a slow brain (see brain.ts) turns `observe()` into a Decision;
 * this fast controller (10 Hz) carries it out: steering, aim, fire, loot
 * pickup, plus always-on reflexes (dodge bullets, stay out of the storm band).
 */
import {
  makeNetId,
  netIdOwner,
  type NetId,
  type PlayerId,
  type Vec2,
} from "../protocol.js";

/** Outgoing client message (no `from`: the server stamps it). */
export type Outgoing = { t: string; seq: number; ts: number; to?: PlayerId } & Record<
  string,
  unknown
>;

export type Incoming = { t: string; from?: string } & Record<string, any>;

export const SHIP_SCRIPT = "player/remote_player.lua";
export const BULLET_SCRIPT = "bullet.lua";
/** Loot prefabs the bot knows how to pick up (state: item, quantity). */
export const LOOT_SCRIPTS: ReadonlySet<string> = new Set(["death_orb.lua", "pickup.lua"]);

// ---- Constants copied from the game's Lua scripts. Keep in sync. ----------
/** map_config.lua WORLD_SIZE / STORM_BAND / STORM.{damage,tick}. */
export const WORLD_SIZE = 20000;
export const STORM_BAND = 500;
export const STORM_DAMAGE = 4;
export const STORM_TICK_SEC = 1;
/** Center of the world = PLAYER_SPAWN in map_config.lua. */
export const DEFAULT_CENTER = { x: 10000, y: 10000 };
/** scenes/aval_cup.lua starts the ship at engine 1: player_upgrades.lua gives 60 + 40 * level. */
export const MAX_SPEED = 100;
export const THRUST = 100;
/** scenes/aval_cup.lua gun = 3: damage 5 + 5 * 3, fire_rate 0.5 + 0.5 * 3 (player_upgrades.lua). */
export const BULLET_SPEED = 1000; // player_shooting.lua
export const BULLET_DAMAGE = 20;
export const FIRE_COOLDOWN_SEC = 0.5;
export const BULLET_LIFETIME_SEC = 2; // bullet_lifetime.lua
/** scenes/aval_cup.lua health.max / inventory.capacity. */
export const MAX_HP = 100;
export const INVENTORY_CAPACITY = 500;
/** map_config.lua SPAWN_SHIELD.time. */
export const SPAWN_SHIELD_SEC = 5;
/** map_config.lua RANKING.send_interval / heartbeat. */
export const RANK_SEND_INTERVAL_SEC = 0.5;
export const RANK_HEARTBEAT_SEC = 5;
/** map_config.lua DEATH_DROP.orbs: the minerals that can drop. */
export const MINERALS: ReadonlySet<string> = new Set(["iron", "gunpowder", "plasma"]);
// ----------------------------------------------------------------------------

export const RESPAWN_DELAY_SEC = 3;
/** Bot spawn clearance from every known ship (best effort; the game uses 2 * CHUNK_SIZE). */
export const SPAWN_CLEAR_BOTS_PX = 2000;
const EDGE_MARGIN = 150;
const EDGE_SOFT = 400;
const PICKUP_RANGE = 60;
const PICKUP_RETRY_SEC = 1;
const DODGE_MISS_PX = 60;
const DODGE_HORIZON_SEC = 0.5;
const THREAT_HORIZON_SEC = 1.5;
const THREAT_MISS_PX = 150;
const STALE_SHIP_SEC = 15;
const ATTACK_RANGE = 1200;

export type Mode = "attack" | "hunt_leader" | "flee" | "collect" | "roam";
export const MODES: readonly Mode[] = ["attack", "hunt_leader", "flee", "collect", "roam"];

export interface Decision {
  mode: Mode;
  targetId: PlayerId | null;
  /** 0 = cautious .. 1 = reckless. */
  aggression: number;
}

export interface EnemyObs {
  slot: number;
  id: PlayerId;
  name: string;
  distance: number;
  hp: number;
  score: number;
  isLeader: boolean;
  approaching: boolean;
}

export interface Observation {
  self: {
    hp: number;
    score: number;
    rank: number;
    players: number;
    pvp: boolean;
    /** Distance (px) to the storm band; negative when inside it. */
    edgeDistance: number;
    /** Seconds of spawn shield left. */
    shield: number;
  };
  enemies: EnemyObs[];
  loot: { distance: number; quantity: number }[];
  threat: { incomingBullets: number; nearestEtaSec: number | null };
}

export interface BotOptions {
  name: string;
  /** Answer host-only requests (snapshot_request) while it is the host. */
  host: boolean;
  /** Ask for pvp via room_settings, only while it is the host. */
  pvp: boolean;
  send: (m: Outgoing) => void;
  /** Wall clock in ms, used only for the `ts` field. */
  now: () => number;
  /** Optional log sink for key events. */
  log?: (line: string) => void;
  /** Random source in [0, 1); injectable for tests. */
  rng?: () => number;
  hitRadius?: number;
}

/** A bullet in flight (own or remote). */
interface RemoteBullet {
  pos: Vec2;
  vel: Vec2;
  dmg: number;
  age: number;
}

interface Ship {
  netId: NetId;
  owner: PlayerId;
  name: string;
  hp: number;
  pos: Vec2;
  vel: Vec2;
  seen: number;
}

interface Loot {
  netId: NetId;
  owner: PlayerId;
  pos: Vec2;
  item: string;
  quantity: number;
  requestedAt: number;
}

const DEFAULT_DECISION: Decision = { mode: "roam", targetId: null, aggression: 0.5 };

export class Bot {
  playerId: PlayerId | null = null;
  hostId: PlayerId | null = null;
  pvp = false;
  hp = MAX_HP;
  dead = false;
  /** Seconds of spawn shield left (damage is ignored while > 0). */
  shield = 0;
  shipNetId: NetId | null = null;
  pos: Vec2 = { ...DEFAULT_CENTER };
  vel: Vec2 = { x: 0, y: 0 };
  /** Acceleration in LOCAL space (like RigidBodyComponent.acceleration). */
  acc: Vec2 = { x: 0, y: 0 };
  rot = 0;
  /** Facing angle in world space (bow = -y at rot 0, so rot = facing + pi/2). */
  heading = 0;
  decision: Decision = { ...DEFAULT_DECISION };
  readonly remoteBullets = new Map<NetId, RemoteBullet>();
  readonly ownBullets = new Map<NetId, RemoteBullet>();
  readonly ships = new Map<NetId, Ship>();
  readonly loot = new Map<NetId, Loot>();
  /** Minerals carried (name -> quantity). */
  readonly inventory = new Map<string, number>();
  /** Other players' totals from rank_score. */
  readonly scores = new Map<PlayerId, number>();

  private seq = 0;
  private netCounter = 0;
  private time = 0;
  private fireTimer = 0;
  private respawnTimer = 0;
  private stormTimer = 0;
  private announcedPvp = false;
  private roamTarget: Vec2 | null = null;
  private roamUntil = 0;
  private strafeDir = 1;
  private strafeUntil = 0;
  private lastScoreSent: number | null = null;
  private lastScoreAt = -Infinity;
  private readonly rng: () => number;
  private readonly hitRadius: number;

  constructor(private readonly o: BotOptions) {
    this.rng = o.rng ?? Math.random;
    this.hitRadius = o.hitRadius ?? 40;
  }

  get isHost(): boolean {
    return this.playerId !== null && this.playerId === this.hostId;
  }

  /** Total minerals carried = ranking score. */
  get score(): number {
    let n = 0;
    for (const q of this.inventory.values()) n += q;
    return n;
  }

  // ---- brain interface --------------------------------------------------

  setDecision(d: Decision): void {
    this.decision = {
      mode: d.mode,
      targetId: d.targetId,
      aggression: Math.max(0, Math.min(1, d.aggression)),
    };
    this.o.log?.(
      `decision: ${d.mode} target=${d.targetId ?? "-"} aggression=${this.decision.aggression.toFixed(2)}`,
    );
  }

  /** Compact snapshot of the situation for the brain. */
  observe(): Observation {
    const ranking = this.ranking();
    const leaderId = this.leaderId(ranking);
    const rank = this.playerId === null ? ranking.length : ranking.findIndex((r) => r.id === this.playerId) + 1;
    const enemies = this.enemyShips()
      .map((s) => ({ s, d: dist(this.pos, s.pos) }))
      .sort((a, b) => a.d - b.d)
      .slice(0, 4)
      .map(({ s, d }, slot): EnemyObs => {
        const toUs = { x: this.pos.x - s.pos.x, y: this.pos.y - s.pos.y };
        const speed = Math.hypot(s.vel.x, s.vel.y);
        return {
          slot,
          id: s.owner,
          name: s.name,
          distance: Math.round(d),
          hp: Math.round(s.hp),
          score: this.scores.get(s.owner) ?? 0,
          isLeader: s.owner === leaderId,
          approaching: speed > 20 && s.vel.x * toUs.x + s.vel.y * toUs.y > 0,
        };
      });
    const loot = [...this.loot.values()]
      .map((l) => ({ distance: Math.round(dist(this.pos, l.pos)), quantity: l.quantity }))
      .sort((a, b) => a.distance - b.distance)
      .slice(0, 3);
    const threats = this.bulletThreats(THREAT_HORIZON_SEC, THREAT_MISS_PX);
    return {
      self: {
        hp: Math.round(this.hp),
        score: this.score,
        rank: Math.max(1, rank),
        players: ranking.length,
        pvp: this.pvp,
        edgeDistance: Math.round(this.edgeDistance() - STORM_BAND),
        shield: Math.round(this.shield * 10) / 10,
      },
      enemies,
      loot,
      threat: {
        incomingBullets: threats.length,
        nearestEtaSec: threats.length ? Math.round(Math.min(...threats) * 100) / 100 : null,
      },
    };
  }

  // ---- incoming ---------------------------------------------------------

  onMessage(m: Incoming): void {
    switch (m.t) {
      case "welcome":
        this.playerId = m.playerId;
        this.hostId = m.hostId;
        this.o.log?.(`welcome: playerId=${m.playerId} host=${m.hostId} peers=${m.peers.length}`);
        this.logHostStatus();
        this.spawnShip();
        this.maybeAnnouncePvp();
        break;
      case "peer_joined":
        if (this.shipNetId && !this.dead) this.send("spawn", this.spawnBody(), m.playerId);
        break;
      case "peer_left":
        this.scores.delete(m.playerId);
        for (const [id, s] of [...this.ships]) if (s.owner === m.playerId) this.ships.delete(id);
        break;
      case "host_changed":
        this.hostId = m.hostId;
        this.logHostStatus();
        this.maybeAnnouncePvp();
        break;
      case "room_settings":
        this.pvp = m.pvp;
        break;
      case "snapshot_request":
        if (this.isHost && this.o.host && m.from) {
          const entities = [];
          if (this.shipNetId && !this.dead) {
            entities.push({
              netId: this.shipNetId,
              owner: this.playerId as string,
              script: SHIP_SCRIPT,
              state: this.shipState(),
            });
          }
          for (const [id, b] of this.ownBullets) entities.push(this.bulletEntity(id, b));
          this.send("snapshot", { entities, settings: { pvp: this.pvp } }, m.from);
        } else if (m.from && this.shipNetId && !this.dead) {
          // Not the host: still hand our ship to a player that lost it (e.g. left the menu)
          this.send("spawn", this.spawnBody(), m.from);
        }
        // map_ranking.lua: a newcomer gets everybody's score directly
        if (m.from && m.from !== this.playerId) this.sendScore(m.from);
        break;
      case "spawn":
        this.onSpawn(m);
        break;
      case "state": {
        const s = this.ships.get(m.netId);
        if (s) {
          s.pos = { ...m.pos };
          s.vel = { ...m.vel };
          s.seen = this.time;
        }
        break;
      }
      case "damage": {
        const s = this.ships.get(m.target);
        if (s && typeof m.newHp === "number") s.hp = m.newHp;
        break;
      }
      case "fire":
        if (m.from && m.from !== this.playerId) {
          this.remoteBullets.set(m.bulletNetId, {
            pos: { ...m.pos },
            vel: { ...m.vel },
            dmg: m.dmg,
            age: 0,
          });
        }
        break;
      case "loot_taken": {
        this.loot.delete(m.lootNetId);
        if (m.by === this.playerId && Array.isArray(m.items)) this.addItems(m.items);
        break;
      }
      case "custom":
        // Echo to test the net_send/net_on round trip from a single client
        if (m.type === "ping" && m.from && m.from !== this.playerId) {
          this.send("custom", { type: "pong", data: m.data }, m.from);
        } else if (
          m.type === "rank_score" &&
          m.from &&
          m.from !== this.playerId &&
          typeof m.data?.total === "number"
        ) {
          this.scores.set(m.from, m.data.total);
        }
        break;
      case "despawn":
      case "death":
        this.remoteBullets.delete(m.netId);
        this.loot.delete(m.netId);
        this.ships.delete(m.netId);
        break;
    }
  }

  private onSpawn(m: Incoming): void {
    if (m.owner === this.playerId) return;
    const st = m.state ?? {};
    if (m.script === SHIP_SCRIPT) {
      this.ships.set(m.netId, {
        netId: m.netId,
        owner: m.owner,
        name: typeof st.name === "string" ? st.name : m.owner,
        hp: typeof st.hp === "number" ? st.hp : MAX_HP,
        pos: { ...st.pos },
        vel: { ...st.vel },
        seen: this.time,
      });
    } else if (LOOT_SCRIPTS.has(m.script)) {
      this.loot.set(m.netId, {
        netId: m.netId,
        owner: m.owner,
        pos: { ...st.pos },
        item: typeof st.item === "string" ? st.item : "iron",
        quantity: typeof st.quantity === "number" ? Math.max(1, Math.floor(st.quantity)) : 1,
        requestedAt: -Infinity,
      });
    }
  }

  // ---- time -------------------------------------------------------------

  tick(dt: number): void {
    if (this.playerId === null) return;
    this.time += dt;
    if (this.dead) {
      this.respawnTimer -= dt;
      if (this.respawnTimer <= 0) this.respawn();
      this.advanceRemoteBullets(dt, false);
      return;
    }

    this.shield = Math.max(0, this.shield - dt);
    this.pruneShips();
    const aim = this.steer(dt);
    this.send("state", { netId: this.shipNetId, ...this.kinematics() });

    this.stormStep(dt);
    if (this.dead) return;
    this.fireStep(dt, aim);
    for (const [id, b] of [...this.ownBullets]) {
      b.age += dt;
      b.pos = { x: b.pos.x + b.vel.x * dt, y: b.pos.y + b.vel.y * dt };
      if (b.age >= BULLET_LIFETIME_SEC) {
        this.ownBullets.delete(id);
        this.send("despawn", { netId: id });
      }
    }
    this.pickupStep();
    this.advanceRemoteBullets(dt, true);
    this.scoreStep();
  }

  // ---- steering ---------------------------------------------------------

  /** Moves the ship toward what the decision asks for. Returns the fire solution, if any. */
  private steer(dt: number): { angle: number; target: Ship } | null {
    const { desired, aim, face } = this.goal();
    let want = desired;

    // Reflex: dodge a bullet that will pass within DODGE_MISS_PX soon
    if (this.pvp) {
      const dodge = this.dodgeVector();
      if (dodge) want = scale(dodge, MAX_SPEED);
    }
    // Reflex: stay out of the storm band
    const lo = STORM_BAND + EDGE_MARGIN;
    const hi = WORLD_SIZE - lo;
    const push = {
      x: this.pos.x < lo + EDGE_SOFT ? (lo + EDGE_SOFT - this.pos.x) / EDGE_SOFT
        : this.pos.x > hi - EDGE_SOFT ? -(this.pos.x - (hi - EDGE_SOFT)) / EDGE_SOFT : 0,
      y: this.pos.y < lo + EDGE_SOFT ? (lo + EDGE_SOFT - this.pos.y) / EDGE_SOFT
        : this.pos.y > hi - EDGE_SOFT ? -(this.pos.y - (hi - EDGE_SOFT)) / EDGE_SOFT : 0,
    };
    const pushLen = Math.hypot(push.x, push.y);
    if (pushLen > 0) {
      const w = Math.min(1, pushLen);
      const inward = scale(unit(push), MAX_SPEED);
      want = { x: want.x + (inward.x - want.x) * w, y: want.y + (inward.y - want.y) * w };
    }

    // Integrate velocity toward the wanted one, limited by thrust and max speed
    const dv = { x: want.x - this.vel.x, y: want.y - this.vel.y };
    const dvLen = Math.hypot(dv.x, dv.y);
    const maxDv = THRUST * dt;
    const k = dvLen > maxDv ? maxDv / dvLen : 1;
    const step = { x: dv.x * k, y: dv.y * k };
    this.vel = { x: this.vel.x + step.x, y: this.vel.y + step.y };
    const speed = Math.hypot(this.vel.x, this.vel.y);
    if (speed > MAX_SPEED) this.vel = scale(this.vel, MAX_SPEED / speed);
    this.pos = { x: this.pos.x + this.vel.x * dt, y: this.pos.y + this.vel.y * dt };

    if (aim) this.heading = aim.angle;
    else if (face !== null) this.heading = face;
    else if (speed > 1) this.heading = Math.atan2(this.vel.y, this.vel.x);
    this.rot = this.heading + Math.PI / 2;
    // local = R(-rot) * world acceleration
    const wa = dt > 0 ? { x: step.x / dt, y: step.y / dt } : { x: 0, y: 0 };
    const cos = Math.cos(this.rot);
    const sin = Math.sin(this.rot);
    this.acc = { x: wa.x * cos + wa.y * sin, y: -wa.x * sin + wa.y * cos };
    return aim;
  }

  /** Desired velocity, plus the fire solution (attack modes) or a facing angle. */
  private goal(): { desired: Vec2; aim: { angle: number; target: Ship } | null; face: number | null } {
    const d = this.decision;
    const maxV = MAX_SPEED;
    switch (d.mode) {
      case "attack":
      case "hunt_leader": {
        const target = this.resolveTarget(d);
        if (!target) return this.roam();
        return this.engage(target, d.aggression);
      }
      case "flee":
        return { desired: this.fleeVector(), aim: null, face: null };
      case "collect": {
        if (this.score >= INVENTORY_CAPACITY) return this.roam();
        const l = this.bestLoot();
        if (!l) return this.roam();
        return { desired: scale(unit(sub(l.pos, this.pos)), maxV), aim: null, face: null };
      }
      default:
        return this.roam();
    }
  }

  private roam(): { desired: Vec2; aim: null; face: null } {
    const lo = STORM_BAND + EDGE_MARGIN + 500;
    const hi = WORLD_SIZE - lo;
    if (
      !this.roamTarget ||
      this.time > this.roamUntil ||
      dist(this.pos, this.roamTarget) < 150
    ) {
      this.roamTarget = { x: lo + this.rng() * (hi - lo), y: lo + this.rng() * (hi - lo) };
      this.roamUntil = this.time + 25;
    }
    return {
      desired: scale(unit(sub(this.roamTarget, this.pos)), MAX_SPEED * 0.6),
      aim: null,
      face: null,
    };
  }

  /** Keep 350-600 px from the target, strafe around it, aim with lead. */
  private engage(target: Ship, aggression: number) {
    const k = 1.2 - 0.4 * aggression; // reckless closes in
    const near = 350 * k;
    const far = 600 * k;
    const d = dist(this.pos, target.pos);
    const toward = unit(sub(target.pos, this.pos));
    let desired: Vec2;
    if (d > far) desired = scale(toward, MAX_SPEED);
    else if (d < near) desired = scale(toward, -MAX_SPEED);
    else {
      if (this.time > this.strafeUntil) {
        this.strafeDir = this.rng() < 0.5 ? -1 : 1;
        this.strafeUntil = this.time + 3 + this.rng() * 2;
      }
      desired = scale({ x: -toward.y * this.strafeDir, y: toward.x * this.strafeDir }, MAX_SPEED * 0.6);
    }
    const angle = leadAngle(this.pos, target.pos, target.vel, BULLET_SPEED) ?? Math.atan2(toward.y, toward.x);
    return { desired, aim: { angle, target }, face: null };
  }

  /** Away from nearby enemies and incoming bullets. */
  private fleeVector(): Vec2 {
    let ax = 0;
    let ay = 0;
    for (const s of this.enemyShips()) {
      const d = Math.max(50, dist(this.pos, s.pos));
      if (d > 2000) continue;
      const w = 1 / d;
      ax += ((this.pos.x - s.pos.x) / d) * w * 1000;
      ay += ((this.pos.y - s.pos.y) / d) * w * 1000;
    }
    if (ax === 0 && ay === 0) {
      // nothing around: head for open space (the center)
      const c = unit(sub(DEFAULT_CENTER, this.pos));
      return scale(c, MAX_SPEED);
    }
    return scale(unit({ x: ax, y: ay }), MAX_SPEED);
  }

  private resolveTarget(d: Decision): Ship | null {
    const byOwner = (id: PlayerId | null) =>
      id === null ? null : this.enemyShips().find((s) => s.owner === id) ?? null;
    if (d.mode === "hunt_leader") {
      const leader = byOwner(this.leaderId(this.ranking()));
      if (leader) return leader;
    }
    const chosen = byOwner(d.targetId);
    if (chosen) return chosen;
    let best: Ship | null = null;
    let bestD = Infinity;
    for (const s of this.enemyShips()) {
      const dd = dist(this.pos, s.pos);
      if (dd < bestD) {
        best = s;
        bestD = dd;
      }
    }
    return best;
  }

  private bestLoot(): Loot | null {
    let best: Loot | null = null;
    let bestV = -Infinity;
    for (const l of this.loot.values()) {
      const v = l.quantity / (dist(this.pos, l.pos) + 300);
      if (v > bestV) {
        best = l;
        bestV = v;
      }
    }
    return best;
  }

  // ---- reflexes ---------------------------------------------------------

  /** Bullets that pass within `missPx` in the next `horizon` s: their ETA to closest approach. */
  private bulletThreats(horizon: number, missPx: number): number[] {
    const out: number[] = [];
    for (const b of this.remoteBullets.values()) {
      const c = closestApproach(this.pos, b);
      if (c.t <= horizon && c.miss <= missPx) out.push(c.t);
    }
    return out;
  }

  private dodgeVector(): Vec2 | null {
    let sum: Vec2 | null = null;
    for (const b of this.remoteBullets.values()) {
      const c = closestApproach(this.pos, b);
      if (c.t > DODGE_HORIZON_SEC || c.miss > DODGE_MISS_PX) continue;
      const v = unit(b.vel);
      // Perpendicular to the bullet, on the side we already are
      const rel = sub(this.pos, b.pos);
      const side = Math.sign(v.x * rel.y - v.y * rel.x) || (this.rng() < 0.5 ? -1 : 1);
      const perp = { x: -v.y * side, y: v.x * side };
      sum = sum ? { x: sum.x + perp.x, y: sum.y + perp.y } : perp;
    }
    return sum ? unit(sum) : null;
  }

  /** Storm band: 4 HP every second while inside (owner-authoritative). */
  private stormStep(dt: number): void {
    const inside = this.edgeDistance() < STORM_BAND;
    if (!inside) {
      this.stormTimer = 0;
      return;
    }
    this.stormTimer += dt;
    while (this.stormTimer >= STORM_TICK_SEC && !this.dead) {
      this.stormTimer -= STORM_TICK_SEC;
      this.takeDamage(STORM_DAMAGE);
    }
  }

  private edgeDistance(): number {
    return Math.min(this.pos.x, this.pos.y, WORLD_SIZE - this.pos.x, WORLD_SIZE - this.pos.y);
  }

  // ---- actions ----------------------------------------------------------

  private fireStep(dt: number, aim: { angle: number; target: Ship } | null): void {
    this.fireTimer = Math.max(0, this.fireTimer - dt);
    if (!aim || !this.pvp || this.fireTimer > 0) return;
    if (dist(this.pos, aim.target.pos) > ATTACK_RANGE) return;
    // A little aim error so bots can be out-flown
    this.heading = aim.angle + (this.rng() - 0.5) * 0.08;
    this.rot = this.heading + Math.PI / 2;
    this.fireTimer = FIRE_COOLDOWN_SEC;
    this.fire();
  }

  private pickupStep(): void {
    if (this.score >= INVENTORY_CAPACITY) return;
    for (const l of this.loot.values()) {
      if (dist(this.pos, l.pos) > PICKUP_RANGE) continue;
      if (this.time - l.requestedAt < PICKUP_RETRY_SEC) continue;
      l.requestedAt = this.time;
      // loot_net.lua: pickup_request goes direct to the loot's owner (the host)
      this.send("pickup_request", { lootNetId: l.netId }, l.owner);
      return;
    }
  }

  private addItems(items: { name?: unknown; quantity?: unknown }[]): void {
    for (const it of items) {
      if (typeof it.name !== "string" || typeof it.quantity !== "number") continue;
      if (!MINERALS.has(it.name) || it.quantity <= 0) continue;
      const room = INVENTORY_CAPACITY - this.score;
      const n = Math.min(Math.floor(it.quantity), room);
      if (n > 0) this.inventory.set(it.name, (this.inventory.get(it.name) ?? 0) + n);
    }
  }

  // ---- ranking ----------------------------------------------------------

  /** Everybody known, ordered like map_ranking.lua: total desc, then id asc. */
  private ranking(): { id: PlayerId; total: number }[] {
    const list: { id: PlayerId; total: number }[] = [];
    for (const [id, total] of this.scores) list.push({ id, total });
    if (this.playerId !== null) list.push({ id: this.playerId, total: this.dead ? 0 : this.score });
    list.sort((a, b) => (a.total !== b.total ? b.total - a.total : a.id < b.id ? -1 : 1));
    return list;
  }

  private leaderId(ranking: { id: PlayerId; total: number }[]): PlayerId | null {
    const first = ranking[0];
    return first && first.total > 0 ? first.id : null;
  }

  private sendScore(to?: PlayerId): void {
    this.send("custom", { type: "rank_score", data: { total: this.dead ? 0 : this.score } }, to);
  }

  private scoreStep(): void {
    const total = this.score;
    const since = this.time - this.lastScoreAt;
    const changed = total !== this.lastScoreSent;
    if ((changed && since >= RANK_SEND_INTERVAL_SEC) || since >= RANK_HEARTBEAT_SEC) {
      this.sendScore();
      this.lastScoreSent = total;
      this.lastScoreAt = this.time;
    }
  }

  // ---- internals --------------------------------------------------------

  private send(t: string, body: Record<string, unknown>, to?: PlayerId): void {
    const m: Outgoing = { t, seq: this.seq++, ts: this.o.now(), ...body };
    if (to !== undefined) m.to = to;
    this.o.send(m);
  }

  private enemyShips(): Ship[] {
    return [...this.ships.values()].filter((s) => s.owner !== this.playerId && s.hp > 0);
  }

  private pruneShips(): void {
    for (const [id, s] of [...this.ships]) {
      if (this.time - s.seen > STALE_SHIP_SEC) this.ships.delete(id);
    }
  }

  private logHostStatus(): void {
    if (this.isHost) this.o.log?.("this bot is the host");
    else if (this.o.host) {
      this.o.log?.(
        `warning: --host given but ${this.hostId} is the host; host paths stay inactive until elected`,
      );
    }
  }

  private maybeAnnouncePvp(): void {
    if (!this.isHost || !this.o.pvp) return;
    this.pvp = true;
    if (this.announcedPvp) return;
    this.announcedPvp = true;
    this.send("room_settings", { pvp: true });
    this.o.log?.("room_settings: pvp=true");
  }

  private nextNetId(): NetId {
    return makeNetId(this.playerId as string, ++this.netCounter);
  }

  private kinematics() {
    return {
      pos: { ...this.pos },
      vel: { ...this.vel },
      rot: this.rot,
      acc: { ...this.acc },
    };
  }

  private shipState() {
    return {
      ...this.kinematics(),
      hp: this.hp,
      name: this.o.name,
      max_hp: MAX_HP,
      max_speed: MAX_SPEED,
      engine: 1,
      gun: 3,
      shield: 4,
    };
  }

  private spawnBody() {
    return {
      netId: this.shipNetId,
      owner: this.playerId,
      script: SHIP_SCRIPT,
      state: this.shipState(),
    };
  }

  /** Random safe point, SPAWN_CLEAR_BOTS_PX away from every known ship (best effort). */
  private pickSpawnPoint(): Vec2 {
    const lo = STORM_BAND + 1000;
    const hi = WORLD_SIZE - lo;
    let best = { x: DEFAULT_CENTER.x, y: DEFAULT_CENTER.y };
    let bestMin = -1;
    for (let i = 0; i < 30; i++) {
      const p = { x: lo + this.rng() * (hi - lo), y: lo + this.rng() * (hi - lo) };
      let min = Infinity;
      for (const s of this.ships.values()) min = Math.min(min, dist(p, s.pos));
      if (min >= SPAWN_CLEAR_BOTS_PX) return p;
      if (min > bestMin) {
        best = p;
        bestMin = min;
      }
    }
    return best;
  }

  private spawnShip(): void {
    this.shipNetId = this.nextNetId();
    this.hp = MAX_HP;
    this.dead = false;
    this.pos = this.pickSpawnPoint();
    this.vel = { x: 0, y: 0 };
    this.acc = { x: 0, y: 0 };
    this.stormTimer = 0;
    this.roamTarget = null;
    this.shield = SPAWN_SHIELD_SEC;
    this.send("spawn", this.spawnBody());
    // map_spawn.lua: the owner announces the spawn shield
    this.send("custom", { type: "spawn_shield", data: { netId: this.shipNetId, t: SPAWN_SHIELD_SEC } });
  }

  private respawn(): void {
    this.o.log?.("respawn");
    this.remoteBullets.clear();
    this.fireTimer = 0;
    this.spawnShip();
  }

  private bulletEntity(id: NetId, b: RemoteBullet) {
    return {
      netId: id,
      owner: this.playerId as string,
      script: BULLET_SCRIPT,
      state: { pos: { ...b.pos }, vel: { ...b.vel }, rot: Math.atan2(b.vel.y, b.vel.x), acc: { x: 0, y: 0 } },
    };
  }

  private fire(): void {
    const id = this.nextNetId();
    const bullet: RemoteBullet = {
      pos: { ...this.pos },
      vel: { x: Math.cos(this.heading) * BULLET_SPEED, y: Math.sin(this.heading) * BULLET_SPEED },
      dmg: BULLET_DAMAGE,
      age: 0,
    };
    this.ownBullets.set(id, bullet);
    this.send("fire", {
      bulletNetId: id,
      shooterNetId: this.shipNetId,
      pos: { ...bullet.pos },
      vel: { ...bullet.vel },
      dmg: bullet.dmg,
    });
    // player_shooting.lua: firing cancels the spawn shield
    if (this.shield > 0) {
      this.shield = 0;
      this.send("custom", { type: "spawn_shield", data: { netId: this.shipNetId, t: 0 } });
    }
  }

  /** Receiver-authoritative damage: only this bot's own HP is ever changed. */
  private advanceRemoteBullets(dt: number, canBeHit: boolean): void {
    for (const [id, b] of [...this.remoteBullets]) {
      const from = b.pos;
      const to = { x: from.x + b.vel.x * dt, y: from.y + b.vel.y * dt };
      b.pos = to;
      b.age += dt;
      if (canBeHit && this.pvp && segmentDistance(this.pos, from, to) <= this.hitRadius) {
        this.remoteBullets.delete(id);
        this.takeDamage(b.dmg, id);
        if (this.dead) return;
      } else if (b.age > 5) {
        this.remoteBullets.delete(id);
      }
    }
  }

  private takeDamage(amount: number, source?: NetId): void {
    if (this.shield > 0) return;
    this.hp -= amount;
    this.o.log?.(`damage: -${amount} hp=${this.hp}`);
    this.send("damage", {
      target: this.shipNetId,
      amount,
      newHp: this.hp,
      ...(source !== undefined ? { source } : {}),
    });
    if (this.hp <= 0) this.die(source);
  }

  private die(source?: NetId): void {
    this.dead = true;
    this.respawnTimer = RESPAWN_DELAY_SEC;
    this.o.log?.("death");
    this.send("death", {
      netId: this.shipNetId,
      ...(source !== undefined ? { killer: netIdOwner(source) } : {}),
    });
    this.send("despawn", { netId: this.shipNetId });
    // map_death_drop.lua: tell the host to drop orbs where we died
    const items = [...this.inventory].map(([name, quantity]) => ({ name, quantity }));
    if (items.length > 0 && this.hostId !== null && this.hostId !== this.playerId) {
      this.send(
        "custom",
        { type: "death_drop", data: { x: this.pos.x, y: this.pos.y, items } },
        this.hostId,
      );
    }
    this.inventory.clear();
    this.sendScore();
    this.lastScoreSent = 0;
    this.lastScoreAt = this.time;
    this.decision = { ...DEFAULT_DECISION };
  }
}

// ---- math -------------------------------------------------------------------

function sub(a: Vec2, b: Vec2): Vec2 {
  return { x: a.x - b.x, y: a.y - b.y };
}

function scale(v: Vec2, k: number): Vec2 {
  return { x: v.x * k, y: v.y * k };
}

function unit(v: Vec2): Vec2 {
  const l = Math.hypot(v.x, v.y);
  return l < 1e-9 ? { x: 0, y: 0 } : { x: v.x / l, y: v.y / l };
}

function dist(a: Vec2, b: Vec2): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

/** Time (>= 0) and distance of the closest approach of a bullet to a point. */
function closestApproach(p: Vec2, b: { pos: Vec2; vel: Vec2 }): { t: number; miss: number } {
  const v2 = b.vel.x * b.vel.x + b.vel.y * b.vel.y;
  const rel = sub(p, b.pos);
  const t = v2 === 0 ? 0 : Math.max(0, (rel.x * b.vel.x + rel.y * b.vel.y) / v2);
  return { t, miss: Math.hypot(rel.x - b.vel.x * t, rel.y - b.vel.y * t) };
}

/** Angle to hit a target moving at constant velocity with a bullet of `speed`, or null. */
export function leadAngle(from: Vec2, tp: Vec2, tv: Vec2, speed: number): number | null {
  const rel = sub(tp, from);
  const a = tv.x * tv.x + tv.y * tv.y - speed * speed;
  const b = 2 * (rel.x * tv.x + rel.y * tv.y);
  const c = rel.x * rel.x + rel.y * rel.y;
  let t: number | null = null;
  if (Math.abs(a) < 1e-9) {
    if (b < 0) t = -c / b;
  } else {
    const disc = b * b - 4 * a * c;
    if (disc >= 0) {
      const r = Math.sqrt(disc);
      const cands = [(-b - r) / (2 * a), (-b + r) / (2 * a)].filter((x) => x > 0);
      if (cands.length) t = Math.min(...cands);
    }
  }
  if (t === null || t > BULLET_LIFETIME_SEC) return null;
  return Math.atan2(rel.y + tv.y * t, rel.x + tv.x * t);
}

/** Distance from point `p` to the segment a-b. */
export function segmentDistance(p: Vec2, a: Vec2, b: Vec2): number {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const len2 = dx * dx + dy * dy;
  const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2));
  return Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
}
