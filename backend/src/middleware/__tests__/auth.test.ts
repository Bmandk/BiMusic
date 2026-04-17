import { describe, it, expect, vi } from "vitest";
import jwt from "jsonwebtoken";

vi.mock("../../config/env.js", () => ({
  env: {
    PORT: 3001,
    NODE_ENV: "test" as const,
    JWT_ACCESS_SECRET: "test-access-secret-at-least-32-chars-long",
    JWT_REFRESH_SECRET: "test-refresh-secret-at-least-32-chars-long",
    JWT_ACCESS_EXPIRY: "15m",
    JWT_REFRESH_EXPIRY: "30d",
    DB_PATH: ":memory:",
    LIDARR_URL: "http://localhost:8686",
    LIDARR_API_KEY: "test",
    MUSIC_LIBRARY_PATH: "/music",
    OFFLINE_STORAGE_PATH: "./data/offline",
    ADMIN_USERNAME: "admin",
    ADMIN_PASSWORD: "adminpassword123",
    TEMP_DIR: "/tmp/bimusic",
  },
}));

import { authenticate, requireAdmin } from "../auth.js";
import type { AuthUser } from "../auth.js";
import type { AppError } from "../errorHandler.js";

const ACCESS_SECRET = "test-access-secret-at-least-32-chars-long";

function makeValidToken(payload: AuthUser): string {
  return jwt.sign(payload, ACCESS_SECRET, {
    algorithm: "HS256",
    expiresIn: "15m",
  });
}

interface MockRequest {
  headers: { authorization?: string };
  query: Record<string, string | string[]>;
  user?: AuthUser;
}

function makeReq(options: {
  authHeader?: string;
  queryToken?: string;
  user?: AuthUser;
}): MockRequest {
  return {
    headers: { authorization: options.authHeader },
    query: options.queryToken ? { token: options.queryToken } : {},
    user: options.user,
  };
}

function makeRes() {
  return {} as never;
}

function makeNext() {
  return vi.fn();
}

function getNextError(next: ReturnType<typeof makeNext>): AppError {
  return (next.mock.calls[0] as [AppError])[0];
}

describe("authenticate", () => {
  it("sets req.user and calls next() for a valid Bearer token", () => {
    const payload: AuthUser = {
      userId: "u1",
      username: "alice",
      isAdmin: false,
    };
    const token = makeValidToken(payload);
    const req = makeReq({ authHeader: `Bearer ${token}` });
    const next = makeNext();

    authenticate(req as never, makeRes(), next);

    expect(next).toHaveBeenCalledTimes(1);
    expect(next).toHaveBeenCalledWith(); // no error
    expect(req.user?.userId).toBe("u1");
    expect(req.user?.username).toBe("alice");
    expect(req.user?.isAdmin).toBe(false);
  });

  it("accepts token via ?token= query parameter", () => {
    const payload: AuthUser = { userId: "u2", username: "bob", isAdmin: false };
    const token = makeValidToken(payload);
    const req = makeReq({ queryToken: token });
    const next = makeNext();

    authenticate(req as never, makeRes(), next);

    expect(next).toHaveBeenCalledTimes(1);
    expect(next).toHaveBeenCalledWith(); // no error
    expect(req.user?.username).toBe("bob");
  });

  it("prefers Authorization header over query token when both present", () => {
    const headerPayload: AuthUser = {
      userId: "header-user",
      username: "header",
      isAdmin: false,
    };
    const queryPayload: AuthUser = {
      userId: "query-user",
      username: "query",
      isAdmin: false,
    };
    const headerToken = makeValidToken(headerPayload);
    const queryToken = makeValidToken(queryPayload);

    const req = makeReq({ authHeader: `Bearer ${headerToken}`, queryToken });
    const next = makeNext();

    authenticate(req as never, makeRes(), next);

    expect(req.user?.username).toBe("header");
  });

  it("calls next with UNAUTHORIZED error when no token is provided", () => {
    const req = makeReq({});
    const next = makeNext();

    authenticate(req as never, makeRes(), next);

    expect(next).toHaveBeenCalledTimes(1);
    const err = getNextError(next);
    expect(err).toBeDefined();
    expect(err.statusCode).toBe(401);
    expect(err.code).toBe("UNAUTHORIZED");
  });

  it("calls next with UNAUTHORIZED error for an invalid token", () => {
    const req = makeReq({ authHeader: "Bearer invalid.token.here" });
    const next = makeNext();

    authenticate(req as never, makeRes(), next);

    expect(next).toHaveBeenCalledTimes(1);
    const err = getNextError(next);
    expect(err.statusCode).toBe(401);
    expect(err.code).toBe("UNAUTHORIZED");
  });

  it("calls next with UNAUTHORIZED error for an expired token", () => {
    const payload: AuthUser = {
      userId: "u3",
      username: "charlie",
      isAdmin: false,
    };
    const expiredToken = jwt.sign(payload, ACCESS_SECRET, {
      algorithm: "HS256",
      expiresIn: -1, // already expired
    });
    const req = makeReq({ authHeader: `Bearer ${expiredToken}` });
    const next = makeNext();

    authenticate(req as never, makeRes(), next);

    const err = getNextError(next);
    expect(err.statusCode).toBe(401);
    expect(err.code).toBe("UNAUTHORIZED");
  });

  it("calls next with UNAUTHORIZED when Authorization header is not a Bearer token", () => {
    const req = makeReq({ authHeader: "Basic somebase64value" });
    const next = makeNext();

    authenticate(req as never, makeRes(), next);

    const err = getNextError(next);
    expect(err.statusCode).toBe(401);
  });

  it("ignores non-string query token values", () => {
    const req: MockRequest = {
      headers: {},
      query: { token: ["token1", "token2"] }, // array, not string
      user: undefined,
    };
    const next = makeNext();

    authenticate(req as never, makeRes(), next);

    const err = getNextError(next);
    expect(err.statusCode).toBe(401);
  });

  it("sets isAdmin true for admin tokens", () => {
    const payload: AuthUser = {
      userId: "admin-id",
      username: "admin",
      isAdmin: true,
    };
    const token = makeValidToken(payload);
    const req = makeReq({ authHeader: `Bearer ${token}` });
    const next = makeNext();

    authenticate(req as never, makeRes(), next);

    expect(req.user?.isAdmin).toBe(true);
  });
});

describe("requireAdmin", () => {
  it("calls next() without error when user is admin", () => {
    const req = makeReq({
      user: { userId: "u1", username: "admin", isAdmin: true },
    });
    const next = makeNext();

    requireAdmin(req as never, makeRes(), next);

    expect(next).toHaveBeenCalledWith(); // no error
  });

  it("calls next with FORBIDDEN error when user is not admin", () => {
    const req = makeReq({
      user: { userId: "u2", username: "alice", isAdmin: false },
    });
    const next = makeNext();

    requireAdmin(req as never, makeRes(), next);

    const err = getNextError(next);
    expect(err.statusCode).toBe(403);
    expect(err.code).toBe("FORBIDDEN");
  });

  it("calls next with FORBIDDEN when req.user is undefined", () => {
    const req = makeReq({});
    const next = makeNext();

    requireAdmin(req as never, makeRes(), next);

    const err = getNextError(next);
    expect(err.statusCode).toBe(403);
    expect(err.code).toBe("FORBIDDEN");
  });
});
