import { describe, it, expect, vi, beforeEach } from 'vitest';
import { executeTask, getExecutorStatus, cancelCurrentTask } from '../agent/executor.js';
import type { TaskRequest } from '../types.js';

vi.mock('node:child_process', () => {
  const mockExecFile = vi.fn();
  return { execFile: mockExecFile };
});

const { execFile } = await import('node:child_process');
const mockExecFile = vi.mocked(execFile);

describe('executor', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('should report idle when no task is running', () => {
    const status = getExecutorStatus();
    expect(status.busy).toBe(false);
    expect(status.queueDepth).toBe(0);
    expect(status.currentTask).toBeNull();
  });

  it('should execute a task and return output', async () => {
    mockExecFile.mockImplementation((_cmd: any, _args: any, _opts: any, cb: any) => {
      const child = {
        stdin: { end: vi.fn() },
        pid: 12345,
        kill: vi.fn(),
      };
      setTimeout(() => cb(null, 'Task completed successfully', ''), 10);
      return child as any;
    });

    const request: TaskRequest = {
      prompt: 'echo hello',
      threadTs: '1.0',
      channel: 'C123',
      messageTs: '1.0',
      userId: 'U123',
    };

    const result = await executeTask(request);
    expect(result.output).toBe('Task completed successfully');
    expect(result.exitCode).toBe(0);
    expect(result.timedOut).toBe(false);
  });

  it('should handle task failure', async () => {
    mockExecFile.mockImplementation((_cmd: any, _args: any, _opts: any, cb: any) => {
      const child = {
        stdin: { end: vi.fn() },
        pid: 12345,
        kill: vi.fn(),
      };
      setTimeout(() => cb(new Error('Process exited with code 1'), 'partial output', 'error text'), 10);
      return child as any;
    });

    const request: TaskRequest = {
      prompt: 'failing task',
      threadTs: '2.0',
      channel: 'C123',
      messageTs: '2.0',
      userId: 'U123',
    };

    const result = await executeTask(request);
    expect(result.exitCode).not.toBe(0);
  });

  it('should reject invalid working directory', async () => {
    const request: TaskRequest = {
      prompt: 'do something',
      workingDir: '/nonexistent/path/that/does/not/exist',
      threadTs: '3.0',
      channel: 'C123',
      messageTs: '3.0',
      userId: 'U123',
    };

    const result = await executeTask(request);
    expect(result.exitCode).toBe(1);
    expect(result.output).toContain('Directory not found');
  });

  it('should include conversation history in prompt when provided', async () => {
    let capturedPrompt = '';
    mockExecFile.mockImplementation((_cmd: any, args: any, _opts: any, cb: any) => {
      capturedPrompt = args[1];
      const child = {
        stdin: { end: vi.fn() },
        pid: 12345,
        kill: vi.fn(),
      };
      setTimeout(() => cb(null, 'done', ''), 10);
      return child as any;
    });

    const request: TaskRequest = {
      prompt: 'now fix the tests',
      conversationHistory: 'User: add a login page\nAgent: I created src/login.tsx',
      threadTs: '4.0',
      channel: 'C123',
      messageTs: '4.0',
      userId: 'U123',
    };

    await executeTask(request);
    expect(capturedPrompt).toContain('previous conversation');
    expect(capturedPrompt).toContain('add a login page');
    expect(capturedPrompt).toContain('now fix the tests');
  });
});
