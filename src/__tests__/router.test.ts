import { describe, it, expect } from 'vitest';
import { parseBuiltInCommand, parseWorkingDir } from '../agent/router.js';

describe('router', () => {
  describe('parseBuiltInCommand', () => {
    it('should detect help command', () => {
      expect(parseBuiltInCommand('help')).toBe('help');
    });

    it('should detect status command', () => {
      expect(parseBuiltInCommand('status')).toBe('status');
    });

    it('should detect cancel command', () => {
      expect(parseBuiltInCommand('cancel')).toBe('cancel');
    });

    it('should detect config workspace command', () => {
      expect(parseBuiltInCommand('config workspace /tmp')).toBe('config');
    });

    it('should detect history command', () => {
      expect(parseBuiltInCommand('history')).toBe('history');
    });

    it('should return null for regular messages', () => {
      expect(parseBuiltInCommand('fix the login bug')).toBeNull();
      expect(parseBuiltInCommand('please help me refactor')).toBeNull();
    });
  });

  describe('parseWorkingDir', () => {
    it('should extract pwd= prefix', () => {
      const result = parseWorkingDir('pwd=/Users/me/project fix the bug');
      expect(result.workingDir).toBe('/Users/me/project');
      expect(result.cleanText).toBe('fix the bug');
    });

    it('should expand ~ in pwd', () => {
      const result = parseWorkingDir('pwd=~/myproject do something');
      expect(result.workingDir).toContain('myproject');
      expect(result.cleanText).toBe('do something');
    });

    it('should return null workingDir when no prefix', () => {
      const result = parseWorkingDir('just a regular message');
      expect(result.workingDir).toBeNull();
      expect(result.cleanText).toBe('just a regular message');
    });
  });
});
