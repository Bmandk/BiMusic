import pino from "pino";

function createLogger() {
  const isDev =
    process.env["NODE_ENV"] === "development" ||
    process.env["NODE_ENV"] === "test";

  if (isDev) {
    return pino({
      level: "debug",
      transport: {
        target: "pino-pretty",
        options: { colorize: true },
      },
    });
  }

  return pino({
    level: "info",
    redact: {
      paths: [
        "req.headers.authorization",
        "res.headers.authorization",
        "req.query.token",
      ],
      censor: "[REDACTED]",
    },
  });
}

export const logger = createLogger();
