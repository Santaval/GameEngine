/**
 * Fake player for testing a game instance alone:
 *   npm run bot -- --host --pvp --duration 30 [--brain jev|heuristic]
 */
import { randomBytes } from "node:crypto";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";
import WebSocket from "ws";
import { PROTOCOL_VERSION } from "../src/protocol.js";
import { Bot } from "../src/bots/botLogic.js";
import { HeuristicBrain, JevBrain, type Brain } from "../src/bots/brain.js";
import { BotDriver } from "../src/bots/manager.js";

export interface RunBotOptions {
  name: string;
  host: boolean;
  pvp: boolean;
  /** Strategy brain (default heuristic). */
  brain?: Brain;
  decisionMs?: number;
  log?: (line: string) => void;
}

export interface RunningBot {
  bot: Bot;
  driver: BotDriver;
  ws: WebSocket;
  /** Resolves when the socket is closed. */
  closed: Promise<void>;
  stop(): void;
}

/** Connects a bot to `url` and drives it at 10 Hz. */
export function runBot(url: string, opts: RunBotOptions): RunningBot {
  const ws = new WebSocket(url);
  const bot = new Bot({
    name: opts.name,
    host: opts.host,
    pvp: opts.pvp,
    log: opts.log,
    send: (m) => {
      if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(m));
    },
    now: () => Date.now(),
  });
  const driver = new BotDriver(bot, opts.brain ?? new HeuristicBrain(), opts.decisionMs ?? 1500);
  let timer: NodeJS.Timeout | undefined;
  let last = Date.now();
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
    timer = setInterval(() => {
      const now = Date.now();
      driver.tick(Math.min(0.25, (now - last) / 1000), now);
      last = now;
    }, 100);
  });
  ws.on("message", (data, isBinary) => {
    if (isBinary) return;
    try {
      bot.onMessage(JSON.parse(data.toString()));
    } catch {
      /* ignore malformed frames */
    }
  });
  ws.on("close", () => {
    clearInterval(timer);
    driver.stop();
  });

  return {
    bot,
    driver,
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
      brain: { type: "string", default: "heuristic" },
      model: { type: "string" },
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
    brain:
      values.brain === "jev"
        ? new JevBrain({ model: values.model ?? "typesafe-ai/jev", log: (e, f) => log(`${e} ${JSON.stringify(f)}`) })
        : new HeuristicBrain(),
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
