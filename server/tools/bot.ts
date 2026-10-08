/**
 * Fake player for testing a game instance alone:
 *   npm run bot -- --host --pvp --duration 30
 */
import { randomBytes } from "node:crypto";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";
import WebSocket from "ws";
import { PROTOCOL_VERSION } from "../src/protocol.js";
import { Bot } from "./botLogic.js";

export interface RunBotOptions {
  name: string;
  host: boolean;
  pvp: boolean;
  cx?: number;
  cy?: number;
  radius?: number;
  fireIntervalSec?: number;
  log?: (line: string) => void;
}

export interface RunningBot {
  bot: Bot;
  ws: WebSocket;
  /** Resolves when the socket is closed. */
  closed: Promise<void>;
  stop(): void;
}

/** Connects a bot to `url` and drives it at 10 Hz. */
export function runBot(url: string, opts: RunBotOptions): RunningBot {
  const ws = new WebSocket(url);
  const bot = new Bot({
    ...opts,
    send: (m) => {
      if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(m));
    },
    now: () => Date.now(),
  });
  let timer: NodeJS.Timeout | undefined;
  const closed = new Promise<void>((resolve) => ws.once("close", () => resolve()));

  ws.on("open", () => {
    ws.send(
      JSON.stringify({
        t: "hello",
        seq: 0,
        ts: Date.now(),
        name: opts.name,
        version: PROTOCOL_VERSION,
      }),
    );
    timer = setInterval(() => bot.tick(0.1), 100);
  });
  ws.on("message", (data, isBinary) => {
    if (isBinary) return;
    try {
      bot.onMessage(JSON.parse(data.toString()));
    } catch {
      /* ignore malformed frames */
    }
  });
  ws.on("close", () => clearInterval(timer));

  return {
    bot,
    ws,
    closed,
    stop() {
      clearInterval(timer);
      ws.close();
    },
  };
}

function main(): void {
  const { values } = parseArgs({
    options: {
      url: { type: "string" },
      name: { type: "string" },
      host: { type: "boolean", default: false },
      pvp: { type: "boolean", default: false },
      radius: { type: "string" },
      cx: { type: "string" },
      cy: { type: "string" },
      "fire-interval": { type: "string" },
      duration: { type: "string" },
    },
  });
  const num = (s: string | undefined): number | undefined => {
    if (s === undefined) return undefined;
    const n = Number(s);
    if (!Number.isFinite(n)) {
      console.error(`invalid number: ${s}`);
      process.exit(2);
    }
    return n;
  };
  const url = values.url ?? process.env.GAME_SERVER ?? "ws://localhost:7777";
  const name = values.name ?? `bot-${randomBytes(2).toString("hex")}`;
  const log = (line: string) => console.log(`[${name}] ${line}`);

  const run = runBot(url, {
    name,
    host: values.host,
    pvp: values.pvp,
    radius: num(values.radius),
    cx: num(values.cx),
    cy: num(values.cy),
    fireIntervalSec: num(values["fire-interval"]),
    log,
  });
  let opened = false;
  run.ws.on("open", () => {
    opened = true;
    log(`connected to ${url}`);
  });
  run.ws.on("error", (err) => {
    console.error(`[${name}] connection error: ${err.message}`);
    if (!opened) process.exit(1);
  });
  run.ws.on("close", (code) => {
    log(`closed (${code})`);
    process.exit(0);
  });

  const stop = () => run.stop();
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
  const duration = num(values.duration);
  if (duration !== undefined) setTimeout(stop, duration * 1000);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
