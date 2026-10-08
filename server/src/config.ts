import { MAX_MESSAGE_BYTES } from "./protocol.js";

export interface Config {
  port: number;
  host: string;
  maxMessageBytes: number;
  rateLimitPerSec: number;
  rateLimitBurst: number;
  heartbeatIntervalMs: number;
  silent: boolean;
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
};

/** Builds the config from environment variables over the defaults. */
export function loadConfig(): Config {
  return {
    ...DEFAULT_CONFIG,
    port: envInt("PORT", DEFAULT_CONFIG.port),
    host: process.env.HOST || DEFAULT_CONFIG.host,
    rateLimitPerSec: envInt("RATE_LIMIT_PER_SEC", DEFAULT_CONFIG.rateLimitPerSec),
    rateLimitBurst: envInt("RATE_LIMIT_BURST", DEFAULT_CONFIG.rateLimitBurst),
    heartbeatIntervalMs: envInt("HEARTBEAT_INTERVAL_MS", DEFAULT_CONFIG.heartbeatIntervalMs),
  };
}
