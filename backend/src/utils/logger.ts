import pino from 'pino';
import path from 'path';

function createLogger() {
  // During env validation, process.env may not be fully parsed yet.
  // Read NODE_ENV and LOG_PATH directly to avoid a circular import.
  const isDev = process.env['NODE_ENV'] === 'development';
  const logPath = process.env['LOG_PATH'] ?? './logs';

  if (isDev) {
    return pino({
      level: 'debug',
      transport: {
        target: 'pino-pretty',
        options: { colorize: true },
      },
    });
  }

  return pino(
    { level: 'info' },
    pino.destination({
      dest: path.join(logPath, 'app.log'),
      sync: false,
    }),
  );
}

export const logger = createLogger();
