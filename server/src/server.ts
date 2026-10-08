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

interface Client {
  id: PlayerId;
  ws: WebSocket;
  bucket: TokenBucket;
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
  const room = new Room<Client>();
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
    if (client.ws.readyState === WebSocket.OPEN) client.ws.send(JSON.stringify(msg));
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

  wss.on("connection", (ws) => {
    const client: Client = {
      id: newPlayerId(),
      ws,
      bucket: new TokenBucket(cfg.rateLimitPerSec, cfg.rateLimitBurst),
      isAlive: true,
    };
    const peers = room.peersOf(client.id);
    room.add(client.id, client);

    const welcome: Omit<Welcome, "from" | "seq" | "ts"> = {
      t: "welcome",
      playerId: client.id,
      hostId: room.hostId as PlayerId,
      peers,
    };
    send(client, serverMsg(welcome));
    const joined: Omit<PeerJoined, "from" | "seq" | "ts"> = {
      t: "peer_joined",
      playerId: client.id,
    };
    broadcast(serverMsg(joined), client.id);
    log("join", { playerId: client.id, hostId: room.hostId, players: room.size });

    ws.on("pong", () => {
      client.isAlive = true;
    });

    ws.on("message", (data: RawData, isBinary: boolean) => {
      if (ws.readyState !== WebSocket.OPEN) return; // already closing (e.g. rate limited)
      if (!client.bucket.take()) {
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
          ws.close(4000, "protocol version mismatch");
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
    });

    ws.on("close", () => {
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
      log("leave", { playerId: client.id, players: room.size });
      if (hostChanged !== null) log("host_change", { hostId: hostChanged });
    });

    ws.on("error", (err) => {
      if (/max payload/i.test(err.message)) {
        log("drop", { playerId: client.id, reason: "oversized" });
      } else {
        log("socket_error", { playerId: client.id, message: err.message });
      }
    });
  });

  const heartbeat = setInterval(() => {
    for (const c of room.clients.values()) {
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
      for (const c of wss.clients) c.terminate();
      return new Promise<void>((resolve, reject) => {
        wss.close(() => http.close((err) => (err ? reject(err) : resolve())));
      });
    },
  };
}
