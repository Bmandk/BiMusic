import pino from "pino";

// Redact token query-param values so JWTs never appear in log files.
// Covers req.query.token (if a full req object is ever logged) and the
// common manual pattern { url: req.url }.
const redact: pino.redactOptions = {
  paths: ["req.query.token", "*.query.token", "url", "req.url"],
  censor: "[REDACTED]",
};

function createLogger() {
  const isDev =
    process.env["NODE_ENV"] === "development" ||
    process.env["NODE_ENV"] === "test";

  if (isDev) {
    return pino({
      level: "debug",
      redact,
      transport: {
        target: "pino-pretty",
        options: { colorize: true },
      },
    });
  }

  return pino({ level: "info", redact });
}

export const logger = createLogger();
