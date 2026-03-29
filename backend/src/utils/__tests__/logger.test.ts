import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtempSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

describe("logger", () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    vi.resetModules();
  });

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  it("creates a pretty-printed logger in development mode", async () => {
    process.env["NODE_ENV"] = "development";
    const { logger } = await import("../../utils/logger.js");
    expect(logger).toBeDefined();
    expect(logger.level).toBe("debug");
  });

  it("creates a file-based logger in production mode", async () => {
    const tempDir = mkdtempSync(join(tmpdir(), "bimusic-log-test-"));
    process.env["NODE_ENV"] = "production";
    process.env["LOG_PATH"] = tempDir;
    const { logger } = await import("../../utils/logger.js");
    expect(logger).toBeDefined();
    expect(logger.level).toBe("info");
  });
});
