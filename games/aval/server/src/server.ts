import { randomBytes } from "node:crypto";
import { createServer as createHttpServer } from "node:http";
import { WebSocketServer, WebSocket, type RawData } from "ws";
import { DEFAULT_CONFIG, type Config } from "./config.js";
import { createLogger } from "./log.js";
import {
  PROTOCOL_VERSION,
  isServerOnlyType,
  validateClientMessage,
  validateMessage,
  type HostChanged,
  type PeerJoined,
  type PeerLeft,
  type PlayerId,
  type Welcome,
} from "./protocol.js";
import { TokenBucket } from "./rateLimit.js";
import { Room } from "./room.js";
import type { Incoming, Outgoing } from "./bots/botLogic.js";
import { createBrain } from "./bots/brain.js";
import { BotManager } from "./bots/manager.js";

interface Client {
  id: PlayerId;
  /** Sockets only; server bots have none. */
  ws?: WebSocket;
  /** Delivers a message to this client (socket write, or hand-off to a bot). */
  deliver(msg: object): void;
  bot: boolean;
  isAlive: boolean;
  name?: string;
}

export interface RelayServer {
  port: number;
  close(): Promise<void>;
}

export async function createServer(opts: Partial<Config> = {}): Promise<RelayServer> {
  const cfg: Config = { ...DEFAULT_CONFIG, ...opts };
  const log = createLogger(cfg.silent);
  const room = new Room<Client>((c) => !c.bot);
  let serverSeq = 0;

  // Plain HTTP answers GET /health (for container health checks); everything
  // else must be a WebSocket upgrade.
  const http = createHttpServer((req, res) => {
    if (req.url === "/health") {
      res.writeHead(200, { "Content-Type": "text/plain" }).end("ok");
    } else {
      res.writeHead(426, { "Content-Type": "text/plain" }).end("Upgrade Required");
    }
  });
  const wss = new WebSocketServer({ server: http, maxPayload: cfg.maxMessageBytes });
  await new Promise<void>((resolve, reject) => {
    http.once("listening", resolve);
    http.once("error", reject);
    http.listen(cfg.port, cfg.host);
  });

  function newPlayerId(): PlayerId {
    let id: PlayerId;
    do {
      id = randomBytes(4).toString("hex");
    } while (room.has(id) || id === "server");
    return id;
  }

  function send(client: Client, msg: unknown): void {
    client.deliver(msg as object);
  }

  function serverMsg<T extends { t: string }>(body: T) {
    const msg = { ...body, from: "server", seq: serverSeq++, ts: Date.now() };
    if (!validateMessage(msg)) throw new Error(`invalid server message: ${body.t}`);
    return msg;
  }

  function broadcast(msg: unknown, exceptId?: PlayerId): void {
    for (const c of room.clients.values()) {
      if (c.id !== exceptId) send(c, msg);
    }
  }

  /** Join: welcome, peer_joined and logs. Shared by sockets and bots. */
  function addClient(client: Client): void {
    const peers = room.peersOf(client.id);
    room.add(client.id, client);

    const welcome: Omit<Welcome, "from" | "seq" | "ts"> = {
      t: "welcome",
      playerId: client.id,
      hostId: room.hostId ?? client.id,
      peers,
    };
    send(client, serverMsg(welcome));
    const joined: Omit<PeerJoined, "from" | "seq" | "ts"> = {
      t: "peer_joined",
      playerId: client.id,
    };
    broadcast(serverMsg(joined), client.id);
    log("join", { playerId: client.id, hostId: room.hostId, players: room.size, bot: client.bot });
    if (!client.bot) manager?.reconcile();
  }

  /** Leave: peer_left, host_changed and logs. Shared by sockets and bots. */
  function removeClient(client: Client): void {
    if (!room.has(client.id)) return;
    const { hostChanged } = room.remove(client.id);
    const left: Omit<PeerLeft, "from" | "seq" | "ts"> = { t: "peer_left", playerId: client.id };
    broadcast(serverMsg(left));
    if (hostChanged !== null) {
      const changed: Omit<HostChanged, "from" | "seq" | "ts"> = {
        t: "host_changed",
        hostId: hostChanged,
      };
      broadcast(serverMsg(changed));
    }
    log("leave", { playerId: client.id, players: room.size, bot: client.bot });
    if (hostChanged !== null) log("host_change", { hostId: hostChanged });
    if (!client.bot) manager?.reconcile();
  }

  /** Validation and routing of one parsed client message (sockets and bots). */
  function routeClientMessage(client: Client, parsed: unknown): void {
    if (!validateClientMessage(parsed)) {
      log("drop", { playerId: client.id, reason: "invalid" });
      return;
    }
    const msg = parsed as { t: string; to?: PlayerId; name?: string; version?: number } & Record<
      string,
      unknown
    >;
    if (isServerOnlyType(msg.t)) {
      log("drop", { playerId: client.id, reason: "server_only_type", t: msg.t });
      return;
    }
    if (msg.t === "hello") {
      if (msg.version !== PROTOCOL_VERSION) {
        log("drop", {
          playerId: client.id,
          reason: "version_mismatch",
          version: msg.version,
        });
        client.ws?.close(4000, "protocol version mismatch");
        return;
      }
      client.name = msg.name;
      log("hello", { playerId: client.id, name: msg.name });
      return;
    }
    msg.from = client.id;
    if (msg.to !== undefined) {
      if (msg.to === client.id) {
        log("drop", { playerId: client.id, reason: "self_target", t: msg.t });
        return;
      }
      const target = room.clients.get(msg.to);
      if (!target) {
        log("drop", { playerId: client.id, reason: "unknown_target", t: msg.t, to: msg.to });
        return;
      }
      send(target, msg);
      return;
    }
    broadcast(msg, client.id);
  }

  wss.on("connection", (ws) => {
    const bucket = new TokenBucket(cfg.rateLimitPerSec, cfg.rateLimitBurst);
    const client: Client = {
      id: newPlayerId(),
      ws,
      bot: false,
      deliver(msg) {
        if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
      },
      isAlive: true,
    };
    addClient(client);

    ws.on("pong", () => {
      client.isAlive = true;
    });

    ws.on("message", (data: RawData, isBinary: boolean) => {
      if (ws.readyState !== WebSocket.OPEN) return; // already closing (e.g. rate limited)
      if (!bucket.take()) {
        log("rate_limited", { playerId: client.id });
        ws.close(1008, "rate limit");
        return;
      }
      if (isBinary) {
        log("drop", { playerId: client.id, reason: "invalid", detail: "binary" });
        return;
      }
      let parsed: unknown;
      try {
        parsed = JSON.parse(data.toString());
      } catch {
        log("drop", { playerId: client.id, reason: "invalid", detail: "json" });
        return;
      }
      routeClientMessage(client, parsed);
    });

    ws.on("close", () => removeClient(client));

    ws.on("error", (err) => {
      if (/max payload/i.test(err.message)) {
        log("drop", { playerId: client.id, reason: "oversized" });
      } else {
        log("socket_error", { playerId: client.id, message: err.message });
      }
    });
  });

  // Server bots: virtual clients that go through the same add/route/remove path
  let manager: BotManager | null = null;
  if (cfg.bots > 0) {
    const brain = createBrain(cfg.botBrain, cfg.botModel, log);
    log("bots_enabled", {
      bots: cfg.bots,
      brain: brain.constructor.name,
      model: cfg.botModel,
      decisionMs: cfg.botDecisionMs,
      skill: cfg.botSkill,
    });
    manager = new BotManager(
      {
        humanCount: () => room.humanCount,
        join(name, handler) {
          const client: Client = {
            id: newPlayerId(),
            bot: true,
            name,
            isAlive: true,
            // setImmediate: never re-enter the bot while it is sending
            deliver(msg) {
              setImmediate(() => {
                try {
                  handler(msg as Incoming);
                } catch (err) {
                  log("bot_error", { message: err instanceof Error ? err.message : String(err) });
                }
              });
            },
          };
          addClient(client);
          return { id: client.id, route: (m: Outgoing) => routeClientMessage(client, m) };
        },
        leave(id) {
          const c = room.clients.get(id);
          if (c) removeClient(c);
        },
      },
      brain,
      {
        bots: cfg.bots,
        decisionMs: cfg.botDecisionMs,
        stepMs: cfg.botStepMs,
        skill: cfg.botSkill,
        debug: cfg.botDebug,
      },
      log,
    );
  }

  const heartbeat = setInterval(() => {
    for (const c of room.clients.values()) {
      if (c.bot || !c.ws) continue;
      if (!c.isAlive) {
        log("heartbeat_timeout", { playerId: c.id });
        c.ws.terminate();
        continue;
      }
      c.isAlive = false;
      c.ws.ping();
    }
  }, cfg.heartbeatIntervalMs);

  const addr = http.address();
  const port = typeof addr === "object" && addr ? addr.port : cfg.port;

  return {
    port,
    close() {
      clearInterval(heartbeat);
      manager?.stop();
      for (const c of wss.clients) c.terminate();
      return new Promise<void>((resolve, reject) => {
        wss.close(() => http.close((err) => (err ? reject(err) : resolve())));
      });
    },
  };
}
