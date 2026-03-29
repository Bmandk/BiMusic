import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov'],
      include: ['src/**/*.ts'],
      exclude: ['src/**/__tests__/**', 'src/types/**', 'src/db/migrations/**', 'src/index.ts'],
      thresholds: {
        lines: 80,
        branches: 75,
      },
    },
  },
});
