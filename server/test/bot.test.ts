import { describe, expect, it, vi } from "vitest";
import WebSocket from "ws";
import { validateClientMessage, validateMessage } from "../src/protocol.js";
import { Bot, MAX_HP, SHIP_SCRIPT, type Outgoing } from "../tools/botLogic.js";
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
  it("spawns, flies in a circle and fires, with only valid messages", async () => {
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

    h.tick(20); // 2 s of sim time: at least one fire (1.5 s interval)
    const states = await collect(obs.client, "state", 20);
    const xs = states.map((s) => s.pos.x);
    expect(new Set(xs).size).toBeGreaterThan(10);
    for (const s of states) expect(s.netId).toBe(spawn.netId);
    const fire = await obs.client.next("fire");
    expect(fire.shooterNetId).toBe(spawn.netId);
    expect(fire.dmg).toBeGreaterThan(0);

    // Seq is strictly increasing and everything validates.
    for (let i = 1; i < h.sent.length; i++) expect(h.sent[i].seq).toBeGreaterThan(h.sent[i - 1].seq);
    for (const m of h.sent) expect(validateClientMessage(m), JSON.stringify(m)).toBe(true);
    for (const m of all) expect(validateMessage(m), JSON.stringify(m)).toBe(true);
    h.ws.terminate();
  });

  it("despawns its bullets after their lifetime", async () => {
    const h = await startBot();
    const obs = await connectObserver();
    h.tick(16); // 1.6 s: first bullet fired
    const fire = await obs.client.next("fire");
    h.tick(20); // +2 s: bullet expires
    expect((await obs.client.next("despawn")).netId).toBe(fire.bulletNetId);
    h.ws.terminate();
  });

  it("announces pvp, takes damage with pvp on and dies at 0 hp", async () => {
    const h = await startBot({ host: true, pvp: true });
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
