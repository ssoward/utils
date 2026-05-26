import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    fileParallelism: false,
    exclude: ['dist/**', 'node_modules/**', 'channel-server/**'],
    env: {
      SLACK_BOT_TOKEN: 'xoxb-test-token',
      SLACK_APP_TOKEN: 'xapp-test-token',
      SLACK_SIGNING_SECRET: 'test-signing-secret',
    },
  },
});
