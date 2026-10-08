import { afterEach, beforeEach } from "vitest";
import WebSocket from "ws";
import { createServer, type RelayServer } from "../src/server.js";
import type { Config } from "../src/config.js";

export type Msg = Record<string, any>;

export class TestClient {
  ws: WebSocket;
  queue: Msg[] = [];
  waiters: Array<{ t: string; resolve: (m: Msg) => void }> = [];

  constructor(port: number, wsOpts?: ConstructorParameters<typeof WebSocket>[2]) {
    this.ws = new WebSocket(`ws://127.0.0.1:${port}`, wsOpts);
    this.ws.on("message", (d, isBinary) => {
      if (isBinary) return;
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

  /** Next message of type `t`; rejects after `timeoutMs`. */
  next(t: string, timeoutMs = 2000): Promise<Msg> {
    const i = this.queue.findIndex((m) => m.t === t);
    if (i >= 0) return Promise.resolve(this.queue.splice(i, 1)[0]);
    return new Promise((resolve, reject) => {
      const waiter = {
        t,
        resolve: (m: Msg) => {
          clearTimeout(timer);
          resolve(m);
        },
      };
      const timer = setTimeout(() => {
        const j = this.waiters.indexOf(waiter);
        if (j >= 0) this.waiters.splice(j, 1);
        reject(new Error(`timed out after ${timeoutMs}ms waiting for "${t}"`));
      }, timeoutMs);
      this.waiters.push(waiter);
    });
  }

  /** Resolves if no message of type `t` arrives within `ms`; rejects otherwise. */
  expectNone(t: string, ms = 150): Promise<void> {
    if (this.queue.some((m) => m.t === t)) {
      return Promise.reject(new Error(`unexpected queued "${t}" message`));
    }
    return new Promise((resolve, reject) => {
      const waiter = {
        t,
        resolve: (m: Msg) => {
          clearTimeout(timer);
          reject(new Error(`unexpected "${t}" message: ${JSON.stringify(m)}`));
        },
      };
      const timer = setTimeout(() => {
        const j = this.waiters.indexOf(waiter);
        if (j >= 0) this.waiters.splice(j, 1);
        resolve();
      }, ms);
      this.waiters.push(waiter);
    });
  }

  closed(): Promise<{ code: number; reason: string }> {
    if (this.ws.readyState === WebSocket.CLOSED) {
      return Promise.reject(new Error("already closed; call closed() before the close happens"));
    }
    return new Promise((resolve) => {
      this.ws.once("close", (code, reason) => resolve({ code, reason: reason.toString() }));
    });
  }

  send(m: Msg): void {
    this.ws.send(JSON.stringify(m));
  }

  sendRaw(s: string): void {
    this.ws.send(s);
  }
}

let counter = 0;

/** Builds a valid client message of type `t` with `seq`/`ts` filled in. */
export function msg(t: string, payload: Msg = {}, seq?: number): Msg {
  return { t, seq: seq ?? counter++, ts: Date.now(), ...payload };
}

export const ZERO = { x: 0, y: 0 };

export function stateMsg(netId: string, x = 0): Msg {
  return msg("state", { netId, pos: { x, y: 0 }, vel: ZERO, rot: 0, acc: ZERO });
}

export interface Connected {
  client: TestClient;
  playerId: string;
  welcome: Msg;
}

/**
 * Registers beforeEach/afterEach that start and stop a relay server on a
 * random port. `connect()` opens a client and awaits its `welcome`.
 */
export function useServer(opts: Partial<Config> = {}) {
  let server: RelayServer | undefined;
  const clients: TestClient[] = [];

  beforeEach(async () => {
    server = await createServer({ port: 0, host: "127.0.0.1", silent: true, ...opts });
  });

  afterEach(async () => {
    for (const c of clients.splice(0)) c.ws.terminate();
    await server?.close();
    server = undefined;
  });

  return {
    server: () => server as RelayServer,
    port: () => (server as RelayServer).port,
    async connect(wsOpts?: ConstructorParameters<typeof WebSocket>[2]): Promise<Connected> {
      const client = new TestClient((server as RelayServer).port, wsOpts);
      clients.push(client);
      await client.open();
      const welcome = await client.next("welcome");
      return { client, playerId: welcome.playerId, welcome };
    },
    track(c: TestClient): TestClient {
      clients.push(c);
      return c;
    },
  };
}
