import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

describe("logger", () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    vi.resetModules();
  });

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  it("creates a pretty-printed debug logger in development mode", async () => {
    process.env["NODE_ENV"] = "development";
    const { logger } = await import("../../utils/logger.js");
    expect(logger).toBeDefined();
    expect(logger.level).toBe("debug");
  });

  it("creates a plain stdout info logger in production mode", async () => {
    process.env["NODE_ENV"] = "production";
    const { logger } = await import("../../utils/logger.js");
    expect(logger).toBeDefined();
    expect(logger.level).toBe("info");
  });
});
