import { MAX_MESSAGE_BYTES } from "./protocol.js";

export interface Config {
  port: number;
  host: string;
  maxMessageBytes: number;
  rateLimitPerSec: number;
  rateLimitBurst: number;
  heartbeatIntervalMs: number;
  silent: boolean;
  /** Fill the room up to this many ships with server bots (0 = none). */
  bots: number;
  botBrain: "auto" | "jev" | "heuristic";
  botModel: string;
  botDecisionMs: number;
  botDebug: boolean;
  /** Delay between adding/removing one bot and the next. */
  botStepMs: number;
}

function envInt(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return fallback;
  const n = Number(raw);
  return Number.isFinite(n) ? n : fallback;
}

export const DEFAULT_CONFIG: Config = {
  port: 7777,
  host: "0.0.0.0",
  maxMessageBytes: MAX_MESSAGE_BYTES,
  rateLimitPerSec: 120,
  rateLimitBurst: 240,
  heartbeatIntervalMs: 5000,
  silent: false,
  bots: 0,
  botBrain: "auto",
  botModel: "typesafe-ai/jev",
  botDecisionMs: 1500,
  botDebug: false,
  botStepMs: 250,
};

function envBrain(): Config["botBrain"] {
  const raw = process.env.BOT_BRAIN;
  return raw === "jev" || raw === "heuristic" || raw === "auto" ? raw : DEFAULT_CONFIG.botBrain;
}

/** Builds the config from environment variables over the defaults. */
export function loadConfig(): Config {
  return {
    ...DEFAULT_CONFIG,
    port: envInt("PORT", DEFAULT_CONFIG.port),
    host: process.env.HOST || DEFAULT_CONFIG.host,
    rateLimitPerSec: envInt("RATE_LIMIT_PER_SEC", DEFAULT_CONFIG.rateLimitPerSec),
    rateLimitBurst: envInt("RATE_LIMIT_BURST", DEFAULT_CONFIG.rateLimitBurst),
    heartbeatIntervalMs: envInt("HEARTBEAT_INTERVAL_MS", DEFAULT_CONFIG.heartbeatIntervalMs),
    bots: Math.max(0, Math.floor(envInt("BOTS", DEFAULT_CONFIG.bots))),
    botBrain: envBrain(),
    botModel: process.env.BOT_MODEL || DEFAULT_CONFIG.botModel,
    botDecisionMs: envInt("BOT_DECISION_MS", DEFAULT_CONFIG.botDecisionMs),
    botDebug: ["1", "true", "yes", "on"].includes((process.env.BOT_DEBUG ?? "").toLowerCase()),
  };
}
