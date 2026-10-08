import { loadConfig } from "./config.js";
import { createLogger } from "./log.js";
import { createServer } from "./server.js";

const config = loadConfig();
const log = createLogger();
const server = await createServer(config);
log("listening", { port: server.port, host: config.host });

let closing = false;
async function shutdown(signal: string): Promise<void> {
  if (closing) return;
  closing = true;
  log("shutdown", { signal });
  await server.close();
  process.exit(0);
}
process.on("SIGINT", () => void shutdown("SIGINT"));
process.on("SIGTERM", () => void shutdown("SIGTERM"));
