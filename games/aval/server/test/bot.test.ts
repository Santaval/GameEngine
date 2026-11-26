import { describe, expect, it, vi } from "vitest";
import WebSocket from "ws";
import { validateClientMessage, validateMessage } from "../src/protocol.js";
import { Bot, INVENTORY_CAPACITY, MAX_HP, tuningFor, SHIP_SCRIPT, STORM_BAND, WORLD_SIZE, type Incoming, type Outgoing } from "../src/bots/botLogic.js";
import { TestClient, msg, useServer, type Msg } from "./helpers.js";

const env = useServer();

interface Harness {
  bot: Bot;
  ws: WebSocket;
  sent: Outgoing[];
  tick(n?: number, dt?: number): void;
}

/** Wires a pure Bot to a real ws connection; ticks are driven by the test. */
async function startBot(opts: { host?: boolean; pvp?: boolean } = {}): Promise<Harness> {
  const ws = new WebSocket(`ws://127.0.0.1:${env.port()}`);
  const sent: Outgoing[] = [];
  let clock = 1000;
  const bot = new Bot({
    name: "test-bot",
    host: opts.host ?? false,
    pvp: opts.pvp ?? false,
    now: () => (clock += 1),
    send: (m) => {
      sent.push(m);
      ws.send(JSON.stringify(m));
    },
  });
  ws.on("message", (d) => bot.onMessage(JSON.parse(d.toString())));
  await new Promise<void>((resolve, reject) => {
    ws.once("open", () => resolve());
    ws.once("error", reject);
  });
  await vi.waitFor(() => expect(bot.playerId).not.toBeNull());
  // Ensure the server processed the bot's welcome-time messages before callers connect.
  return {
    bot,
    ws,
    sent,
    tick(n = 1, dt = 0.1) {
      for (let i = 0; i < n; i++) bot.tick(dt);
    },
  };
}

async function connectObserver(): Promise<{ client: TestClient; playerId: string }> {
  const { client, playerId } = await env.connect();
  return { client, playerId };
}

/** Drains messages of type `t` that the observer has received so far plus `count - queued` more. */
async function collect(c: TestClient, t: string, count: number): Promise<Msg[]> {
  const out: Msg[] = [];
  for (let i = 0; i < count; i++) out.push(await c.next(t));
  return out;
}

function fireAt(bot: Bot, from: string, id: number, dmg: number): Msg {
  return msg("fire", {
    bulletNetId: `${from}:${id}`,
    shooterNetId: `${from}:1`,
    pos: { ...bot.pos },
    vel: { x: 0, y: 0 },
    dmg,
  });
}

describe("fake-client bot", () => {
  it("spawns with a shield, moves and sends only valid messages", async () => {
    const h = await startBot();
    const obs = await connectObserver();
    const all: Msg[] = [];
    obs.client.ws.on("message", (d) => all.push(JSON.parse(d.toString())));

    // The newcomer gets a direct spawn of the bot's ship.
    const spawn = await obs.client.next("spawn");
    expect(spawn.script).toBe(SHIP_SCRIPT);
    expect(spawn.owner).toBe(h.bot.playerId);
    expect(spawn.state.name).toBe("test-bot");
    expect(spawn.state.hp).toBe(MAX_HP);
    const shield = h.sent.find((m) => m.t === "custom" && m.type === "spawn_shield");
    expect(shield?.data).toEqual({ netId: spawn.netId, t: 5 });

    h.tick(20); // 2 s of sim time
    const states = await collect(obs.client, "state", 20);
    expect(new Set(states.map((s) => s.pos.x)).size).toBeGreaterThan(10);
    for (const s of states) expect(s.netId).toBe(spawn.netId);

    // Seq is strictly increasing and everything validates.
    for (let i = 1; i < h.sent.length; i++) expect(h.sent[i].seq).toBeGreaterThan(h.sent[i - 1].seq);
    for (const m of h.sent) expect(validateClientMessage(m), JSON.stringify(m)).toBe(true);
    for (const m of all) expect(validateMessage(m), JSON.stringify(m)).toBe(true);
    h.ws.terminate();
  });

  it("announces pvp, takes damage with pvp on and dies at 0 hp", async () => {
    const h = await startBot({ host: true, pvp: true });
    h.bot.shield = 0;
    const obs = await connectObserver();
    await obs.client.next("spawn");
    expect(h.sent.some((m) => m.t === "room_settings" && m.pvp === true)).toBe(true);

    const hp: number[] = [];
    for (let i = 0; i < 3; i++) {
      obs.client.send(fireAt(h.bot, obs.playerId, i + 10, 40));
      await vi.waitFor(() => expect(h.bot.remoteBullets.size).toBe(1));
      h.tick(1);
      const dmg = await obs.client.next("damage");
      expect(dmg.target).toBe(h.bot.shipNetId);
      expect(dmg.amount).toBe(40);
      expect(dmg.source).toBe(`${obs.playerId}:${i + 10}`);
      hp.push(dmg.newHp);
    }
    expect(hp).toEqual([60, 20, -20]);
    const death = await obs.client.next("death");
    expect(death.killer).toBe(obs.playerId);
    expect(death.netId).toBe(h.bot.shipNetId);
    expect((await obs.client.next("despawn")).netId).toBe(death.netId);
    for (const m of h.sent) expect(validateClientMessage(m)).toBe(true);
    h.ws.terminate();
  });

  it("respawns with full hp and a new ship id after dying", async () => {
    const h = await startBot({ host: true, pvp: true });
    h.bot.shield = 0;
    const obs = await connectObserver();
    const first = await obs.client.next("spawn");
    obs.client.send(fireAt(h.bot, obs.playerId, 10, 500));
    await vi.waitFor(() => expect(h.bot.remoteBullets.size).toBe(1));
    h.tick(1);
    await obs.client.next("death");
    expect(h.bot.dead).toBe(true);
    h.tick(31); // > 3 s
    const second = await obs.client.next("spawn");
    expect(second.netId).not.toBe(first.netId);
    expect(second.state.hp).toBe(MAX_HP);
    expect(h.bot.hp).toBe(MAX_HP);
    h.ws.terminate();
  });

  it("ignores player bullets when pvp is off", async () => {
    const h = await startBot({ host: true, pvp: false });
    h.bot.shield = 0;
    const obs = await connectObserver();
    await obs.client.next("spawn");
    obs.client.send(fireAt(h.bot, obs.playerId, 10, 40));
    await vi.waitFor(() => expect(h.bot.remoteBullets.size).toBe(1));
    h.tick(3);
    await obs.client.expectNone("damage");
    expect(h.bot.hp).toBe(MAX_HP);
    h.ws.terminate();
  });

  it("answers a snapshot_request with a direct snapshot when it is the host", async () => {
    const h = await startBot({ host: true, pvp: true });
    const obs = await connectObserver();
    await obs.client.next("spawn");
    obs.client.send(msg("snapshot_request"));
    const snap = await obs.client.next("snapshot");
    expect(validateMessage(snap)).toBe(true);
    expect(snap.from).toBe(h.bot.playerId);
    expect(snap.settings).toEqual({ pvp: true });
    expect(snap.entities.map((e: Msg) => e.netId)).toContain(h.bot.shipNetId);
    h.ws.terminate();
  });

  it("does not answer snapshot_request when it is not the host", async () => {
    const host = await env.connect();
    const h = await startBot({ host: true });
    await host.client.next("spawn");
    expect(h.bot.isHost).toBe(false);
    host.client.send(msg("snapshot_request"));
    await host.client.expectNone("snapshot");
    h.ws.terminate();
  });

  it("re-sends its ship spawn directly on snapshot_request when it is not the host", async () => {
    const host = await env.connect();
    const h = await startBot({ host: true });
    await host.client.next("spawn");
    expect(h.bot.isHost).toBe(false);
    host.client.send(msg("snapshot_request"));
    const spawn = await host.client.next("spawn");
    expect(spawn.netId).toBe(h.bot.shipNetId);
    expect(spawn.script).toBe("player/remote_player.lua");
    h.ws.terminate();
  });

  it("takes over host duties after host_changed", async () => {
    const host = await env.connect();
    const h = await startBot({ host: true, pvp: true });
    await host.client.next("spawn");
    expect(h.sent.some((m) => m.t === "room_settings")).toBe(false);
    host.client.ws.close();
    await vi.waitFor(() => expect(h.bot.isHost).toBe(true));
    expect(h.sent.filter((m) => m.t === "room_settings")).toHaveLength(1);
    h.ws.terminate();
  });

  it("answers a custom ping with a direct pong carrying the same data", async () => {
    const h = await startBot();
    const obs = await connectObserver();
    await obs.client.next("spawn");
    obs.client.send(msg("custom", { type: "ping", data: { n: 1 } }));
    const pong = await obs.client.next("custom");
    expect(validateMessage(pong)).toBe(true);
    expect(pong.type).toBe("pong");
    expect(pong.data).toEqual({ n: 1 });
    expect(pong.from).toBe(h.bot.playerId);
    h.ws.terminate();
  });
});

// ---- controller unit tests (no sockets) ------------------------------------

interface Unit {
  bot: Bot;
  sent: Outgoing[];
  of(t: string, type?: string): Outgoing[];
  tick(n?: number, dt?: number): void;
}

/** A bot welcomed into a room whose host is "host1", with a fixed rng. */
function unitBot(opts: { pvp?: boolean; skill?: number; rng?: () => number } = {}): Unit {
  const sent: Outgoing[] = [];
  const bot = new Bot({
    name: "u",
    host: false,
    pvp: false,
    now: () => 1,
    rng: opts.rng ?? (() => 0.5),
    skill: opts.skill,
    send: (m) => sent.push(m),
  });
  bot.onMessage({ t: "welcome", playerId: "me", hostId: "host1", peers: ["host1"] });
  if (opts.pvp) bot.onMessage({ t: "room_settings", pvp: true });
  bot.shield = 0;
  return {
    bot,
    sent,
    of: (t, type) => sent.filter((m) => m.t === t && (type === undefined || m.type === type)),
    tick(n = 1, dt = 0.1) {
      for (let i = 0; i < n; i++) bot.tick(dt);
    },
  };
}

function enemySpawn(owner: string, x: number, y: number, vx = 0, vy = 0): Incoming {
  return {
    t: "spawn",
    from: owner,
    netId: `${owner}:1`,
    owner,
    script: SHIP_SCRIPT,
    state: { pos: { x, y }, vel: { x: vx, y: vy }, rot: 0, acc: { x: 0, y: 0 }, hp: 100, name: owner },
  };
}

function lootSpawn(id: number, x: number, y: number, quantity = 5): Incoming {
  return {
    t: "spawn",
    from: "host1",
    netId: `host1:${id}`,
    owner: "host1",
    script: "death_orb.lua",
    state: { pos: { x, y }, vel: { x: 0, y: 0 }, rot: 0, acc: { x: 0, y: 0 }, item: "iron", quantity },
  };
}

describe("bot controller", () => {
  it("steers back inside the storm band and takes storm damage while in it", () => {
    const u = unitBot();
    u.bot.pos = { x: 200, y: 10000 };
    u.bot.vel = { x: -50, y: 0 };
    u.tick(11); // just over 1 s inside the band
    expect(u.of("damage").length).toBeGreaterThanOrEqual(1);
    expect(u.of("damage")[0].amount).toBe(4);
    u.tick(200);
    expect(u.bot.pos.x).toBeGreaterThan(STORM_BAND);
    expect(u.bot.pos.x).toBeLessThan(WORLD_SIZE - STORM_BAND);
  });

  it("dodges a bullet on a collision course (pvp on, sharp bot)", () => {
    const u = unitBot({ pvp: true, skill: 1 });
    u.bot.pos = { x: 10000, y: 10000 };
    u.bot.vel = { x: 0, y: 0 };
    u.bot.onMessage({
      t: "fire",
      from: "e1",
      bulletNetId: "e1:5",
      shooterNetId: "e1:1",
      pos: { x: 9700, y: 10000 },
      vel: { x: 1000, y: 0 },
      dmg: 20,
    });
    u.tick(1);
    expect(Math.abs(u.bot.vel.y)).toBeGreaterThan(5);
  });

  it("collect: sends pickup_request to the loot owner when in range", () => {
    const u = unitBot();
    u.bot.pos = { x: 10000, y: 10000 };
    u.bot.onMessage(lootSpawn(7, 10040, 10000));
    u.bot.setDecision({ mode: "collect", targetId: null, aggression: 0.5 });
    u.tick(3);
    const req = u.of("pickup_request");
    expect(req).toHaveLength(1);
    expect(req[0].lootNetId).toBe("host1:7");
    expect(req[0].to).toBe("host1");
    expect(validateClientMessage(req[0])).toBe(true);
  });

  it("loot_taken for this bot adds to the score and sends rank_score", () => {
    const u = unitBot();
    u.bot.onMessage(lootSpawn(7, 100, 100));
    u.bot.onMessage({
      t: "loot_taken",
      from: "host1",
      lootNetId: "host1:7",
      by: "me",
      items: [{ name: "iron", quantity: 5 }],
    });
    expect(u.bot.score).toBe(5);
    expect(u.bot.loot.size).toBe(0);
    u.tick(6);
    const scores = u.of("custom", "rank_score");
    expect(scores.some((m) => (m.data as { total: number }).total === 5)).toBe(true);
    for (const m of scores) expect(validateClientMessage(m)).toBe(true);
  });

  it("ignores loot_taken for somebody else", () => {
    const u = unitBot();
    u.bot.onMessage({ t: "loot_taken", from: "host1", lootNetId: "x:1", by: "other", items: [{ name: "iron", quantity: 5 }] });
    expect(u.bot.score).toBe(0);
  });

  it("on death sends death_drop to the host, then reports score 0", () => {
    const u = unitBot({ pvp: true });
    u.bot.onMessage({ t: "loot_taken", from: "host1", lootNetId: "x:1", by: "me", items: [{ name: "iron", quantity: 10 }] });
    u.bot.onMessage({
      t: "fire",
      from: "e1",
      bulletNetId: "e1:5",
      shooterNetId: "e1:1",
      pos: { ...u.bot.pos },
      vel: { x: 0, y: 0 },
      dmg: 500,
    });
    u.tick(1);
    expect(u.bot.dead).toBe(true);
    const drop = u.of("custom", "death_drop");
    expect(drop).toHaveLength(1);
    expect(drop[0].to).toBe("host1");
    expect((drop[0].data as { items: unknown[] }).items).toEqual([{ name: "iron", quantity: 10 }]);
    expect(validateClientMessage(drop[0])).toBe(true);
    expect(u.bot.score).toBe(0);
    const last = u.of("custom", "rank_score").pop();
    expect((last?.data as { total: number }).total).toBe(0);
  });

  it("does not fire at humans when pvp is off, fires when it is on", () => {
    const off = unitBot({ pvp: false });
    off.bot.pos = { x: 10000, y: 10000 };
    off.bot.onMessage(enemySpawn("e1", 10500, 10000));
    off.bot.setDecision({ mode: "attack", targetId: "e1", aggression: 0.5 });
    off.tick(30);
    expect(off.of("fire")).toHaveLength(0);

    const on = unitBot({ pvp: true });
    on.bot.pos = { x: 10000, y: 10000 };
    on.bot.onMessage(enemySpawn("e1", 10500, 10000));
    on.bot.setDecision({ mode: "attack", targetId: "e1", aggression: 0.5 });
    on.tick(30);
    const fires = on.of("fire");
    expect(fires.length).toBeGreaterThan(2);
    expect(validateClientMessage(fires[0])).toBe(true);
    expect((fires[0].vel as { x: number }).x).toBeGreaterThan(900);
  });

  it("firing cancels the spawn shield and announces it", () => {
    const u = unitBot({ pvp: true });
    u.bot.shield = 5;
    u.bot.pos = { x: 10000, y: 10000 };
    u.bot.onMessage(enemySpawn("e1", 10500, 10000));
    u.bot.setDecision({ mode: "attack", targetId: "e1", aggression: 0.5 });
    u.tick(20);
    expect(u.bot.shield).toBe(0);
    expect(u.of("custom", "spawn_shield").some((m) => (m.data as { t: number }).t === 0)).toBe(true);
  });

  it("observe() ranks players and lists nearest enemies and loot", () => {
    const u = unitBot({ pvp: true });
    u.bot.pos = { x: 10000, y: 10000 };
    u.bot.onMessage(enemySpawn("e1", 10500, 10000));
    u.bot.onMessage(enemySpawn("e2", 12000, 10000));
    u.bot.onMessage({ t: "custom", from: "e2", type: "rank_score", data: { total: 40 } });
    u.bot.onMessage(lootSpawn(7, 10100, 10000, 3));
    const o = u.bot.observe();
    expect(o.enemies.map((e) => e.id)).toEqual(["e1", "e2"]);
    expect(o.enemies[1].isLeader).toBe(true);
    expect(o.self.rank).toBe(2);
    expect(o.loot).toEqual([{ distance: 100, quantity: 3 }]);
  });
});

// ---- scan, farm, mine, skill ------------------------------------------------

function scanResult(rocks: unknown[], planets?: unknown[]): Incoming {
  return { t: "custom", from: "host1", type: "bot_scan_result", data: { rocks, ...(planets ? { planets } : {}) } };
}

const PLANET = { x: 14000, y: 10000, range: 600, body_radius: 100, mineral: "plasma", mine_interval: 2 };

describe("bot host scan", () => {
  it("sends bot_scan to the host on spawn and every 2 s, with planets until they arrive", () => {
    const u = unitBot();
    u.tick(1);
    let scans = u.of("custom", "bot_scan");
    expect(scans).toHaveLength(1);
    expect(scans[0].to).toBe("host1");
    expect(scans[0].data).toMatchObject({ r: 2000, planets: true });
    expect(validateClientMessage(scans[0])).toBe(true);

    u.tick(20); // +2 s
    scans = u.of("custom", "bot_scan");
    expect(scans).toHaveLength(2);
    expect((scans[1].data as { planets?: boolean }).planets).toBe(true);

    u.bot.onMessage(scanResult([], [PLANET]));
    u.tick(20);
    scans = u.of("custom", "bot_scan");
    expect(scans).toHaveLength(3);
    expect((scans[2].data as { planets?: boolean }).planets).toBeUndefined();
    expect(u.bot.planets).toHaveLength(1);
  });

  it("does not scan when it is the host itself", () => {
    const sent: Outgoing[] = [];
    const bot = new Bot({ name: "u", host: true, pvp: false, now: () => 1, send: (m) => sent.push(m) });
    bot.onMessage({ t: "welcome", playerId: "me", hostId: "me", peers: [] });
    for (let i = 0; i < 30; i++) bot.tick(0.1);
    expect(sent.some((m) => m.type === "bot_scan")).toBe(false);
  });

  it("tracks rocks from scan results and drops them on map_rock_destroyed", () => {
    const u = unitBot();
    u.bot.pos = { x: 10000, y: 10000 };
    u.tick(1);
    u.bot.onMessage(
      scanResult([
        { id: "1:1:0", x: 10300, y: 10000, radius: 26, hp: 40 },
        { id: "1:1:1", x: 10000, y: 10800, radius: 52, hp: 80 },
      ]),
    );
    expect([...u.bot.rocks.keys()].sort()).toEqual(["1:1:0", "1:1:1"]);
    expect(u.bot.observe().rocks).toEqual({ count: 2, nearestDistance: expect.any(Number) });

    u.bot.onMessage({ t: "custom", from: "host1", type: "map_rock_destroyed", data: { id: "1:1:0" } });
    expect([...u.bot.rocks.keys()]).toEqual(["1:1:1"]);
    // a stale result must not bring a destroyed rock back
    u.tick(20);
    u.bot.onMessage(scanResult([{ id: "1:1:0", x: 10300, y: 10000, radius: 26, hp: 40 }]));
    expect(u.bot.rocks.has("1:1:0")).toBe(false);
    // and a result replaces the chunk rocks inside the scanned circle
    expect(u.bot.rocks.has("1:1:1")).toBe(false);
  });

  it("ignores scan results and rock news that do not come from the host", () => {
    const u = unitBot();
    u.tick(1);
    u.bot.onMessage({ ...scanResult([{ id: "a", x: 1, y: 1, radius: 1, hp: 1 }]), from: "other" });
    expect(u.bot.rocks.size).toBe(0);
  });

  it("tracks asteroid fragments from spawn and removes them on despawn", () => {
    const u = unitBot();
    u.bot.onMessage({
      t: "spawn",
      from: "host1",
      netId: "host1:9",
      owner: "host1",
      script: "asteroid.lua",
      state: { pos: { x: 100, y: 100 }, vel: { x: 50, y: 0 }, rot: 0, acc: { x: 0, y: 0 } },
    });
    expect(u.bot.rocks.get("host1:9")?.fragment).toBe(true);
    u.tick(10);
    expect(u.bot.rocks.get("host1:9")?.pos.x).toBeGreaterThan(140);
    u.bot.onMessage({ t: "despawn", from: "host1", netId: "host1:9" });
    expect(u.bot.rocks.size).toBe(0);
  });
});

describe("bot farming", () => {
  it("farm: fires at the rock within the aim-error bound, even with pvp off", () => {
    const u = unitBot();
    u.bot.pos = { x: 10000, y: 10000 };
    u.tick(1);
    u.bot.onMessage(scanResult([{ id: "1:1:0", x: 10400, y: 10000, radius: 26, hp: 40 }]));
    u.bot.setDecision({ mode: "farm", targetId: null, aggression: 0.3 });
    u.tick(30);
    const fires = u.of("fire");
    expect(fires.length).toBeGreaterThan(1);
    const bound = u.bot.tuning.aimError;
    for (const f of fires) {
      const v = f.vel as { x: number; y: number };
      const pos = f.pos as { x: number; y: number };
      const want = Math.atan2(10000 - pos.y, 10400 - pos.x);
      const diff = Math.abs(Math.atan2(Math.sin(Math.atan2(v.y, v.x) - want), Math.cos(Math.atan2(v.y, v.x) - want)));
      expect(diff).toBeLessThanOrEqual(bound + 1e-9);
      expect(validateClientMessage(f)).toBe(true);
    }
  });

  it("farm: skips rocks inside a planet's gravity", () => {
    const u = unitBot();
    u.bot.pos = { x: 13000, y: 10000 };
    u.tick(1);
    u.bot.onMessage(scanResult([{ id: "1:1:0", x: 13600, y: 10000, radius: 26, hp: 40 }], [PLANET]));
    expect(u.bot.observe().rocks.count).toBe(0);
    u.bot.setDecision({ mode: "farm", targetId: null, aggression: 0.3 });
    u.tick(30);
    expect(u.of("fire")).toHaveLength(0);
  });

  it("farm: goes for a nearby orb before the next rock", () => {
    const u = unitBot();
    u.bot.pos = { x: 10000, y: 10000 };
    u.tick(1);
    u.bot.onMessage(scanResult([{ id: "1:1:0", x: 10000, y: 11500, radius: 26, hp: 40 }]));
    u.bot.onMessage(lootSpawn(7, 10040, 10000));
    u.bot.setDecision({ mode: "farm", targetId: null, aggression: 0.3 });
    u.tick(3);
    expect(u.of("pickup_request")).toHaveLength(1);
  });
});

describe("bot mining", () => {
  it("mine: +1 mineral every mine_interval inside range, stops at capacity, sends rank_score", () => {
    const u = unitBot();
    u.bot.pos = { x: 10000, y: 10000 };
    u.tick(1);
    u.bot.onMessage(scanResult([], [PLANET]));
    expect(u.bot.observe().planet).toEqual({ distance: 4000, mineral: "plasma" });

    u.bot.pos = { x: 14000 - 360, y: 10000 }; // inside range (600)
    u.bot.vel = { x: 0, y: 0 };
    u.bot.setDecision({ mode: "mine", targetId: null, aggression: 0.3 });
    u.tick(61); // 6.1 s -> 3 minerals
    expect(u.bot.inventory.get("plasma")).toBe(3);
    expect(dist2(u.bot.pos, PLANET)).toBeLessThan(PLANET.range);
    expect(dist2(u.bot.pos, PLANET)).toBeGreaterThan(PLANET.body_radius * 2);
    const scores = u.of("custom", "rank_score");
    expect(scores.some((m) => (m.data as { total: number }).total === 3)).toBe(true);

    u.bot.inventory.set("plasma", INVENTORY_CAPACITY);
    u.tick(100);
    expect(u.bot.score).toBe(INVENTORY_CAPACITY);
  });

  it("does not mine outside a planet's range", () => {
    const u = unitBot();
    u.bot.pos = { x: 10000, y: 10000 };
    u.tick(1);
    u.bot.onMessage(scanResult([], [PLANET]));
    u.tick(50);
    expect(u.bot.score).toBe(0);
  });

  it("mine: flies to the planet and starts mining", () => {
    const u = unitBot();
    u.bot.pos = { x: 13200, y: 10000 };
    u.tick(1);
    u.bot.onMessage(scanResult([], [PLANET]));
    u.bot.setDecision({ mode: "mine", targetId: null, aggression: 0.3 });
    u.tick(300);
    expect(u.bot.score).toBeGreaterThan(5);
  });
});

function dist2(a: { x: number; y: number }, b: { x: number; y: number }): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

describe("bot skill", () => {
  it("skill 0 vs 1 changes cooldown, aim error, dodge, range and reaction", () => {
    const easy = tuningFor(0);
    const sharp = tuningFor(1);
    expect(easy).toEqual({ aimError: 0.35, fireCooldown: 1.2, dodgeChance: 0.15, attackRange: 700, reactionDelay: 0.8 });
    expect(sharp.aimError).toBeCloseTo(0.05);
    expect(sharp.fireCooldown).toBeCloseTo(0.5);
    expect(sharp.dodgeChance).toBeCloseTo(0.85);
    expect(sharp.attackRange).toBeCloseTo(1200);
    expect(sharp.reactionDelay).toBeCloseTo(0.2);
  });

  it("a skilled bot fires more often than an easy one", () => {
    const count = (skill: number) => {
      const u = unitBot({ pvp: true, skill });
      u.bot.pos = { x: 10000, y: 10000 };
      u.bot.onMessage(enemySpawn("e1", 10500, 10000));
      u.bot.setDecision({ mode: "attack", targetId: "e1", aggression: 0.5 });
      u.tick(100);
      return u.of("fire").length;
    };
    expect(count(1)).toBeGreaterThan(count(0));
  });

  it("an easy bot (skill 0) often ignores an incoming bullet", () => {
    const bullet = (u: Unit) =>
      u.bot.onMessage({
        t: "fire",
        from: "e1",
        bulletNetId: "e1:5",
        shooterNetId: "e1:1",
        pos: { x: 9700, y: 10000 },
        vel: { x: 1000, y: 0 },
        dmg: 20,
      });
    const easy = unitBot({ pvp: true, skill: 0, rng: () => 0.5 }); // 0.5 > 0.15: ignores it
    easy.bot.pos = { x: 10000, y: 10000 };
    bullet(easy);
    easy.tick(1);
    expect(Math.abs(easy.bot.vel.y)).toBeLessThan(1);
  });

  it("observe() exposes skill, hold and the provoker for 6 s", () => {
    const u = unitBot({ pvp: true, skill: 0.8 });
    u.bot.pos = { x: 10000, y: 10000 };
    u.bot.onMessage(enemySpawn("e1", 10500, 10000));
    expect(u.bot.observe().self).toMatchObject({ skill: 0.8, holdFree: INVENTORY_CAPACITY, recentlyAttackedBy: null, canInitiateFights: true });
    u.bot.onMessage({
      t: "fire",
      from: "e1",
      bulletNetId: "e1:5",
      shooterNetId: "e1:1",
      pos: { ...u.bot.pos },
      vel: { x: 0, y: 0 },
      dmg: 10,
    });
    u.tick(1);
    expect(u.bot.observe().self.recentlyAttackedBy).toBe(0);
    u.tick(70, 0.1);
    expect(u.bot.observe().self.recentlyAttackedBy).toBeNull();
    expect(unitBot({ skill: 0.35 }).bot.observe().self.canInitiateFights).toBe(false);
  });
});
