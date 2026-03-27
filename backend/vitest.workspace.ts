import { defineWorkspace } from 'vitest/config';

export default defineWorkspace([
  {
    test: {
      name: 'unit',
      include: ['src/**/__tests__/**/*.test.ts'],
      environment: 'node',
    },
  },
  {
    test: {
      name: 'integration',
      include: ['tests/integration/**/*.test.ts'],
      environment: 'node',
      setupFiles: ['tests/setup.ts'],
      pool: 'forks',
      testTimeout: 15000,
    },
  },
]);
