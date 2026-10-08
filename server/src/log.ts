export type Logger = (event: string, fields?: Record<string, unknown>) => void;

/** Structured JSON-lines logger writing to stdout. */
export function createLogger(silent = false): Logger {
  if (silent) return () => {};
  return (event, fields) => {
    process.stdout.write(JSON.stringify({ ts: new Date().toISOString(), event, ...fields }) + "\n");
  };
}
