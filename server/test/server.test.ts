import { describe, expect, it } from "vitest";
import WebSocket from "ws";
import { MAX_MESSAGE_BYTES, PROTOCOL_VERSION } from "../src/protocol.js";
import { TestClient, msg, stateMsg, useServer } from "./helpers.js";

describe("relay server", () => {
  const env = useServer();
  const { connect } = env;

  it("welcomes a joiner, announces peer_joined and peer_left", async () => {
    const a = await connect();
    expect(a.welcome.hostId).toBe(a.playerId);
    expect(a.welcome.peers).toEqual([]);
    expect(a.welcome.from).toBe("server");

    const b = await connect();
    expect(b.welcome.hostId).toBe(a.playerId);
    expect(b.welcome.peers).toEqual([a.playerId]);
    expect(b.playerId).not.toBe(a.playerId);
    expect((await a.client.next("peer_joined")).playerId).toBe(b.playerId);

    b.client.ws.close();
    expect((await a.client.next("peer_left")).playerId).toBe(b.playerId);
  });

  it("lets two clients see each other's messages with from stamped", async () => {
    const a = await connect();
    const b = await connect();
    a.client.send({ ...stateMsg(`${a.playerId}:1`), pos: { x: 1, y: 2 }, from: "spoofed" });
    const got = await b.client.next("state");
    expect(got.from).toBe(a.playerId);
    expect(got.pos).toEqual({ x: 1, y: 2 });
  });

  it("sends peer_left then host_changed when the host disconnects", async () => {
    const a = await connect();
    const b = await connect();
    a.client.ws.close();
    const left = await b.client.next("peer_left");
    expect(left.playerId).toBe(a.playerId);
    const changed = await b.client.next("host_changed");
    expect(changed.hostId).toBe(b.playerId);
    expect(left.seq).toBeLessThan(changed.seq);
  });

  it("migrates the host in join order", async () => {
    const a = await connect();
    const b = await connect();
    const c = await connect();

    a.client.ws.close();
    expect((await b.client.next("host_changed")).hostId).toBe(b.playerId);
    expect((await c.client.next("host_changed")).hostId).toBe(b.playerId);

    b.client.ws.close();
    expect((await c.client.next("host_changed")).hostId).toBe(c.playerId);

    // A non-host leaving does not change the host.
    const d = await connect();
    await c.client.next("peer_joined");
    d.client.ws.close();
    await c.client.next("peer_left");
    await c.client.expectNone("host_changed");

    // A newcomer is told who the current host is.
    const e = await connect();
    expect(e.welcome.hostId).toBe(c.playerId);
  });

  it("delivers directed messages only to the target", async () => {
    const a = await connect();
    const b = await connect();
    const c = await connect();
    a.client.send(msg("despawn", { netId: `${a.playerId}:1`, to: b.playerId }));
    const got = await b.client.next("despawn");
    expect(got.from).toBe(a.playerId);
    await c.client.expectNone("despawn");
  });

  it("drops directed messages to unknown ids or to self, keeping the sender connected", async () => {
    const a = await connect();
    const b = await connect();
    a.client.send(msg("despawn", { netId: `${a.playerId}:1`, to: "nobody" }));
    a.client.send(msg("despawn", { netId: `${a.playerId}:2`, to: a.playerId }));
    await b.client.expectNone("despawn");
    await a.client.expectNone("despawn");
    expect(a.client.ws.readyState).toBe(WebSocket.OPEN);
    a.client.send(msg("despawn", { netId: `${a.playerId}:3` }));
    expect((await b.client.next("despawn")).netId).toBe(`${a.playerId}:3`);
  });

  it("does not echo broadcasts to the sender", async () => {
    const a = await connect();
    const b = await connect();
    a.client.send(stateMsg(`${a.playerId}:1`));
    await b.client.next("state");
    await a.client.expectNone("state");
  });

  it("closes the connection with 1009 on an oversized message", async () => {
    const a = await connect();
    const b = await connect();
    const closed = a.client.closed();
    a.client.sendRaw(" ".repeat(MAX_MESSAGE_BYTES + 1));
    expect((await closed).code).toBe(1009);
    await b.client.next("peer_left");
    expect(b.client.queue.filter((m) => m.t !== "host_changed")).toEqual([]);
  });

  it("drops invalid messages without closing the socket", async () => {
    const peer = await connect();
    const a = await connect();
    await peer.client.next("peer_joined");

    a.client.sendRaw("not json {{{");
    a.client.sendRaw(JSON.stringify(msg("state", { netId: `${a.playerId}:1` }))); // bad payload
    a.client.sendRaw(JSON.stringify(msg("bogus", {})));
    a.client.sendRaw(JSON.stringify(msg("welcome", { playerId: "x", hostId: "x", peers: [] })));
    a.client.sendRaw(JSON.stringify({ t: "state" })); // missing envelope fields
    a.client.ws.send(Buffer.from([1, 2, 3]), { binary: true });
    a.client.send(msg("despawn", { netId: `${a.playerId}:9` })); // valid marker

    expect((await peer.client.next("despawn")).netId).toBe(`${a.playerId}:9`);
    // Ordering is preserved, so anything leaked would already be queued.
    expect(peer.client.queue).toEqual([]);
    expect(a.client.ws.readyState).toBe(WebSocket.OPEN);
  });

  it("rejects a hello with the wrong protocol version (4000)", async () => {
    const a = await connect();
    const closed = a.client.closed();
    a.client.send(msg("hello", { name: "x", version: PROTOCOL_VERSION + 1 }));
    expect((await closed).code).toBe(4000);
  });

  it("accepts a correct hello and does not forward it", async () => {
    const a = await connect();
    const b = await connect();
    a.client.send(msg("hello", { name: "alice", version: PROTOCOL_VERSION }));
    await b.client.expectNone("hello");
    expect(a.client.ws.readyState).toBe(WebSocket.OPEN);
  });
});

describe("relay server rate limit", () => {
  const env = useServer({ rateLimitPerSec: 10, rateLimitBurst: 10 });

  it("disconnects a flooding client with 1008 and spares others", async () => {
    const flooder = await env.connect();
    const calm = await env.connect();
    const closed = flooder.client.closed();
    for (let i = 0; i < 50; i++) flooder.client.send(stateMsg(`${flooder.playerId}:1`, i));
    expect((await closed).code).toBe(1008);

    calm.client.send(msg("despawn", { netId: `${calm.playerId}:1` }));
    expect(calm.client.ws.readyState).toBe(WebSocket.OPEN);
    await calm.client.next("peer_left");
  });
});

describe("relay server heartbeat", () => {
  const env = useServer({ heartbeatIntervalMs: 50 });

  it("terminates a client that stops answering pings", async () => {
    const dead = env.track(new TestClient(env.port(), { autoPong: false }));
    await dead.open();
    const closed = dead.closed();
    const { code } = await Promise.race([
      closed,
      new Promise<never>((_, rej) => setTimeout(() => rej(new Error("not terminated")), 1500)),
    ]);
    expect(code).toBe(1006);
  });

  it("keeps a responsive client connected", async () => {
    const a = await env.connect();
    await a.client.expectNone("peer_left", 250);
    expect(a.client.ws.readyState).toBe(WebSocket.OPEN);
  });
});
