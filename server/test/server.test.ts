import { afterEach, beforeEach, describe, expect, it } from "vitest";
import WebSocket from "ws";
import { createServer, type RelayServer } from "../src/server.js";

type Msg = Record<string, any>;

class TestClient {
  ws: WebSocket;
  queue: Msg[] = [];
  waiters: Array<{ t: string; resolve: (m: Msg) => void }> = [];

  constructor(port: number) {
    this.ws = new WebSocket(`ws://127.0.0.1:${port}`);
    this.ws.on("message", (d) => {
      const m = JSON.parse(d.toString());
      const i = this.waiters.findIndex((w) => w.t === m.t);
      if (i >= 0) this.waiters.splice(i, 1)[0].resolve(m);
      else this.queue.push(m);
    });
  }

  open(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.ws.once("open", () => resolve());
      this.ws.once("error", reject);
    });
  }

  next(t: string): Promise<Msg> {
    const i = this.queue.findIndex((m) => m.t === t);
    if (i >= 0) return Promise.resolve(this.queue.splice(i, 1)[0]);
    return new Promise((resolve) => this.waiters.push({ t, resolve }));
  }

  send(m: Msg): void {
    this.ws.send(JSON.stringify(m));
  }
}

describe("relay server", () => {
  let server: RelayServer;
  const clients: TestClient[] = [];

  beforeEach(async () => {
    server = await createServer({ port: 0, host: "127.0.0.1", silent: true });
  });

  afterEach(async () => {
    for (const c of clients.splice(0)) c.ws.terminate();
    await server.close();
  });

  async function connect(): Promise<TestClient> {
    const c = new TestClient(server.port);
    clients.push(c);
    await c.open();
    return c;
  }

  it("lets two clients see each other's messages with from stamped", async () => {
    const a = await connect();
    const wa = await a.next("welcome");
    const b = await connect();
    const wb = await b.next("welcome");
    expect(wa.hostId).toBe(wa.playerId);
    expect(wb.hostId).toBe(wa.playerId);
    expect(wb.peers).toEqual([wa.playerId]);
    expect((await a.next("peer_joined")).playerId).toBe(wb.playerId);

    a.send({
      t: "state", seq: 1, ts: 1, netId: `${wa.playerId}:1`,
      pos: { x: 1, y: 2 }, vel: { x: 0, y: 0 }, rot: 0, acc: { x: 0, y: 0 },
      from: "spoofed",
    });
    const got = await b.next("state");
    expect(got.from).toBe(wa.playerId);
  });

  it("sends peer_left then host_changed when the host disconnects", async () => {
    const a = await connect();
    const wa = await a.next("welcome");
    const b = await connect();
    const wb = await b.next("welcome");
    a.ws.close();
    const left = await b.next("peer_left");
    expect(left.playerId).toBe(wa.playerId);
    const changed = await b.next("host_changed");
    expect(changed.hostId).toBe(wb.playerId);
    expect(left.seq).toBeLessThan(changed.seq);
  });
});
