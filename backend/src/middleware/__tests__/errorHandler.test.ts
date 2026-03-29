import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("../../config/env.js", () => ({
  env: {
    PORT: 3001,
    NODE_ENV: "test" as const,
    JWT_ACCESS_SECRET: "test-access-secret-at-least-32-chars-long",
    JWT_REFRESH_SECRET: "test-refresh-secret-at-least-32-chars-long",
    JWT_ACCESS_EXPIRY: "15m",
    JWT_REFRESH_EXPIRY: "30d",
    DB_PATH: ":memory:",
    LOG_PATH: "./logs",
    LIDARR_URL: "http://localhost:8686",
    LIDARR_API_KEY: "test",
    MUSIC_LIBRARY_PATH: "/music",
    OFFLINE_STORAGE_PATH: "./data/offline",
    ADMIN_USERNAME: "admin",
    ADMIN_PASSWORD: "adminpassword123",
    TEMP_DIR: "/tmp/bimusic",
    API_BASE_URL: "http://localhost:3000",
  },
}));

vi.mock("../../utils/logger.js", () => ({
  logger: {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
    child: vi.fn(() => ({
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
      debug: vi.fn(),
    })),
  },
}));

import { logger } from "../../utils/logger.js";
import { createError, notFoundHandler, errorHandler } from "../errorHandler.js";
import type { AppError } from "../errorHandler.js";

function makeRes() {
  const res = {
    locals: { requestId: "req-123" },
    status: vi.fn().mockReturnThis(),
    json: vi.fn().mockReturnThis(),
    setHeader: vi.fn().mockReturnThis(),
    end: vi.fn().mockReturnThis(),
  };
  return res;
}

function makeReq(method = "GET", path = "/test") {
  return { method, path } as never;
}

function makeNext() {
  return vi.fn();
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("createError", () => {
  it("creates an error with statusCode, code, and message", () => {
    const err = createError(404, "NOT_FOUND", "Resource missing");
    expect(err).toBeInstanceOf(Error);
    expect(err.message).toBe("Resource missing");
    expect(err.statusCode).toBe(404);
    expect(err.code).toBe("NOT_FOUND");
  });

  it("creates a 500 internal error", () => {
    const err = createError(500, "INTERNAL_ERROR", "Something went wrong");
    expect(err.statusCode).toBe(500);
    expect(err.code).toBe("INTERNAL_ERROR");
  });

  it("creates a 401 unauthorized error", () => {
    const err = createError(401, "UNAUTHORIZED", "Not authenticated");
    expect(err.statusCode).toBe(401);
    expect(err.code).toBe("UNAUTHORIZED");
  });
});

describe("notFoundHandler", () => {
  it("calls next with a 404 NOT_FOUND error", () => {
    const req = makeReq("GET", "/nonexistent");
    const next = makeNext();

    notFoundHandler(req, makeRes() as never, next);

    expect(next).toHaveBeenCalledTimes(1);
    const err = (next.mock.calls[0] as [AppError])[0];
    expect(err.statusCode).toBe(404);
    expect(err.code).toBe("NOT_FOUND");
    expect(err.message).toContain("GET");
    expect(err.message).toContain("/nonexistent");
  });

  it("includes the HTTP method and path in the error message", () => {
    const req = makeReq("POST", "/api/unknown");
    const next = makeNext();

    notFoundHandler(req, makeRes() as never, next);

    const err = (next.mock.calls[0] as [AppError])[0];
    expect(err.message).toContain("POST");
    expect(err.message).toContain("/api/unknown");
  });
});

describe("errorHandler", () => {
  it("sends the correct status code and JSON body for a 4xx error", () => {
    const err = createError(400, "BAD_REQUEST", "Invalid input");
    const res = makeRes();

    errorHandler(err, makeReq(), res as never, makeNext());

    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json).toHaveBeenCalledWith({
      error: { code: "BAD_REQUEST", message: "Invalid input" },
    });
  });

  it("logs warn for 4xx errors", () => {
    const err = createError(422, "VALIDATION_ERROR", "Field required");
    const res = makeRes();

    errorHandler(err, makeReq(), res as never, makeNext());

    expect(logger.warn).toHaveBeenCalled();
    expect(logger.error).not.toHaveBeenCalled();
  });

  it("sends the correct status code and JSON body for a 5xx error in test env", () => {
    const err = createError(500, "INTERNAL_ERROR", "Database crashed");
    const res = makeRes();

    errorHandler(err, makeReq(), res as never, makeNext());

    // In test (non-production), the real message is sent
    expect(res.status).toHaveBeenCalledWith(500);
    expect(res.json).toHaveBeenCalledWith({
      error: { code: "INTERNAL_ERROR", message: "Database crashed" },
    });
  });

  it("logs error for 5xx errors", () => {
    const err = createError(503, "SERVICE_UNAVAILABLE", "Down");
    const res = makeRes();

    errorHandler(err, makeReq(), res as never, makeNext());

    expect(logger.error).toHaveBeenCalled();
    expect(logger.warn).not.toHaveBeenCalled();
  });

  it("defaults statusCode to 500 when err.statusCode is missing", () => {
    const err = new Error("unexpected") as AppError;
    const res = makeRes();

    errorHandler(err, makeReq(), res as never, makeNext());

    expect(res.status).toHaveBeenCalledWith(500);
  });

  it("defaults code to INTERNAL_ERROR when err.code is missing", () => {
    const err = new Error("unknown") as AppError;
    const res = makeRes();

    errorHandler(err, makeReq(), res as never, makeNext());

    const call = (res.json.mock.calls[0] as [{ error: { code: string } }])[0];
    expect(call.error.code).toBe("INTERNAL_ERROR");
  });

  it("returns generic message for 5xx in production environment", async () => {
    // Temporarily override the env mock for this test
    const envModule = (await import("../../config/env.js")) as unknown as {
      env: Record<string, unknown>;
    };
    const originalEnv = envModule.env["NODE_ENV"];
    envModule.env["NODE_ENV"] = "production";

    const err = createError(
      500,
      "INTERNAL_ERROR",
      "Sensitive internal details",
    );
    const res = makeRes();

    errorHandler(err, makeReq(), res as never, makeNext());

    expect(res.json).toHaveBeenCalledWith({
      error: { code: "INTERNAL_ERROR", message: "Internal server error" },
    });

    // Restore
    envModule.env["NODE_ENV"] = originalEnv ?? "test";
  });

  it("sends real message for 5xx in non-production environment", () => {
    const err = createError(502, "LIDARR_ERROR", "Lidarr is down");
    const res = makeRes();

    errorHandler(err, makeReq(), res as never, makeNext());

    expect(res.json).toHaveBeenCalledWith({
      error: { code: "LIDARR_ERROR", message: "Lidarr is down" },
    });
  });

  it("handles a plain Error without statusCode (logs as 5xx)", () => {
    const err = new Error("Something broke") as AppError;
    const res = makeRes();

    errorHandler(err, makeReq(), res as never, makeNext());

    expect(logger.error).toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(500);
  });

  it("passes requestId from res.locals to logger", () => {
    const err = createError(500, "ERR", "Boom");
    const res = makeRes();
    res.locals = { requestId: "test-request-id" };

    errorHandler(err, makeReq(), res as never, makeNext());

    expect(logger.error).toHaveBeenCalledWith(
      expect.objectContaining({ requestId: "test-request-id" }),
      expect.any(String),
    );
  });
});
