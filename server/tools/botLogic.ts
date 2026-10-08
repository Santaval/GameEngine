/**
 * Pure fake-player logic. No sockets, no clock, no process access: the caller
 * feeds it incoming messages (`onMessage`), time steps (`tick`) and receives
 * outgoing messages through `send`.
 */
import {
  makeNetId,
  netIdOwner,
  type NetId,
  type PlayerId,
  type Vec2,
} from "../src/protocol.js";

/** Outgoing client message (no `from`: the server stamps it). */
export type Outgoing = { t: string; seq: number; ts: number; to?: PlayerId } & Record<
  string,
  unknown
>;

export type Incoming = { t: string; from?: string } & Record<string, any>;

export const SHIP_SCRIPT = "player/remote_player.lua";
export const BULLET_SCRIPT = "bullet.lua";
export const BULLET_SPEED = 600;
export const BULLET_LIFETIME_SEC = 2;
export const RESPAWN_DELAY_SEC = 3;
export const MAX_HP = 100;

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
  cx?: number;
  cy?: number;
  radius?: number;
  /** Angular speed in rad/s. */
  angularSpeed?: number;
  fireIntervalSec?: number;
  hitRadius?: number;
}

/** A bullet in flight (own or remote). */
interface RemoteBullet {
  pos: Vec2;
  vel: Vec2;
  dmg: number;
  age: number;
}

export class Bot {
  playerId: PlayerId | null = null;
  hostId: PlayerId | null = null;
  pvp = false;
  hp = MAX_HP;
  dead = false;
  shipNetId: NetId | null = null;
  pos: Vec2 = { x: 0, y: 0 };
  vel: Vec2 = { x: 0, y: 0 };
  acc: Vec2 = { x: 0, y: 0 };
  rot = 0;
  readonly remoteBullets = new Map<NetId, RemoteBullet>();
  readonly ownBullets = new Map<NetId, RemoteBullet>();

  private seq = 0;
  private netCounter = 0;
  private angle = 0;
  private fireTimer = 0;
  private respawnTimer = 0;
  private announcedPvp = false;

  private readonly cx: number;
  private readonly cy: number;
  private readonly radius: number;
  private readonly omega: number;
  private readonly fireInterval: number;
  private readonly hitRadius: number;

  constructor(private readonly o: BotOptions) {
    this.cx = o.cx ?? 0;
    this.cy = o.cy ?? 0;
    this.radius = o.radius ?? 300;
    this.omega = o.angularSpeed ?? 0.5;
    this.fireInterval = o.fireIntervalSec ?? 1.5;
    this.hitRadius = o.hitRadius ?? 20;
    this.updateKinematics();
  }

  get isHost(): boolean {
    return this.playerId !== null && this.playerId === this.hostId;
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
        }
        break;
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
      case "despawn":
        this.remoteBullets.delete(m.netId);
        break;
      case "death":
        this.remoteBullets.delete(m.netId);
        break;
    }
  }

  // ---- time -------------------------------------------------------------

  tick(dt: number): void {
    if (this.playerId === null) return;
    if (this.dead) {
      this.respawnTimer -= dt;
      if (this.respawnTimer <= 0) this.respawn();
      this.advanceRemoteBullets(dt, false);
      return;
    }

    this.angle += this.omega * dt;
    this.updateKinematics();
    this.send("state", { netId: this.shipNetId, ...this.kinematics() });

    this.fireTimer += dt;
    if (this.fireTimer >= this.fireInterval) {
      this.fireTimer -= this.fireInterval;
      this.fire();
    }
    for (const [id, b] of [...this.ownBullets]) {
      b.age += dt;
      b.pos = { x: b.pos.x + b.vel.x * dt, y: b.pos.y + b.vel.y * dt };
      if (b.age >= BULLET_LIFETIME_SEC) {
        this.ownBullets.delete(id);
        this.send("despawn", { netId: id });
      }
    }

    this.advanceRemoteBullets(dt, true);
  }

  // ---- internals --------------------------------------------------------

  private send(t: string, body: Record<string, unknown>, to?: PlayerId): void {
    const m: Outgoing = { t, seq: this.seq++, ts: this.o.now(), ...body };
    if (to !== undefined) m.to = to;
    this.o.send(m);
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

  private updateKinematics(): void {
    const a = this.angle;
    const r = this.radius;
    const w = this.omega;
    this.pos = { x: this.cx + r * Math.cos(a), y: this.cy + r * Math.sin(a) };
    this.vel = { x: -r * w * Math.sin(a), y: r * w * Math.cos(a) };
    this.acc = { x: -r * w * w * Math.cos(a), y: -r * w * w * Math.sin(a) };
    this.rot = r * w === 0 ? 0 : Math.atan2(this.vel.y, this.vel.x);
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
    return { ...this.kinematics(), hp: this.hp, name: this.o.name };
  }

  private spawnBody() {
    return {
      netId: this.shipNetId,
      owner: this.playerId,
      script: SHIP_SCRIPT,
      state: this.shipState(),
    };
  }

  private spawnShip(): void {
    this.shipNetId = this.nextNetId();
    this.hp = MAX_HP;
    this.dead = false;
    this.send("spawn", this.spawnBody());
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
      vel: { x: Math.cos(this.rot) * BULLET_SPEED, y: Math.sin(this.rot) * BULLET_SPEED },
      dmg: 10,
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

  private takeDamage(amount: number, bulletNetId: NetId): void {
    this.hp -= amount;
    this.o.log?.(`damage: -${amount} hp=${this.hp}`);
    this.send("damage", {
      target: this.shipNetId,
      amount,
      newHp: this.hp,
      source: bulletNetId,
    });
    if (this.hp <= 0) {
      this.dead = true;
      this.respawnTimer = RESPAWN_DELAY_SEC;
      this.o.log?.("death");
      this.send("death", { netId: this.shipNetId, killer: netIdOwner(bulletNetId) });
      this.send("despawn", { netId: this.shipNetId });
    }
  }
}

/** Distance from point `p` to the segment a-b. */
export function segmentDistance(p: Vec2, a: Vec2, b: Vec2): number {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const len2 = dx * dx + dy * dy;
  const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2));
  return Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
}
