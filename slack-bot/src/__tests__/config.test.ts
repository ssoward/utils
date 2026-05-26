import { describe, it, expect } from 'vitest';
import { config } from '../config.js';

describe('config', () => {
  it('should have agent configuration', () => {
    expect(config.agent).toBeDefined();
    expect(config.agent.workingDir).toBeDefined();
    expect(typeof config.agent.maxTurns).toBe('number');
    expect(typeof config.agent.timeoutMs).toBe('number');
    expect(typeof config.agent.allowedTools).toBe('string');
    expect(typeof config.agent.sessionTtlHours).toBe('number');
  });

  it('should not have monitoring config', () => {
    expect(config).not.toHaveProperty('hookPort');
    expect(config).not.toHaveProperty('schedulerIntervalMinutes');
    expect(config).not.toHaveProperty('thresholds');
  });
});
