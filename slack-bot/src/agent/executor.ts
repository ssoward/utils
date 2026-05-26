import { execFile } from 'node:child_process';
import fs from 'node:fs';
import { config } from '../config.js';
import { logger } from '../utils/logger.js';
import type { TaskRequest, TaskResult } from '../types.js';

const COMPONENT = 'executor';
const MAX_SLACK_CHARS = 3000;
const MAX_BUFFER = 10 * 1024 * 1024; // 10 MB

interface ExecutorStatus {
  busy: boolean;
  queueDepth: number;
  currentTask: { threadTs: string; channel: string; startedAt: string } | null;
}

let currentChild: ReturnType<typeof execFile> | null = null;
let currentTaskInfo: { threadTs: string; channel: string; startedAt: string } | null = null;
const taskQueue: Array<{ request: TaskRequest; resolve: (r: TaskResult) => void }> = [];
let isProcessing = false;

export function getExecutorStatus(): ExecutorStatus {
  return {
    busy: isProcessing,
    queueDepth: taskQueue.length,
    currentTask: currentTaskInfo,
  };
}

export function cancelCurrentTask(): boolean {
  if (currentChild && currentChild.pid) {
    currentChild.kill('SIGTERM');
    return true;
  }
  return false;
}

function expandHome(p: string): string {
  if (p.startsWith('~/') || p === '~') {
    return p.replace('~', process.env.HOME || '/tmp');
  }
  return p;
}

function truncateForSlack(text: string): string {
  if (text.length <= MAX_SLACK_CHARS) return text;
  return text.slice(0, MAX_SLACK_CHARS - 20) + '\n\n...(truncated)';
}

function buildPrompt(request: TaskRequest): string {
  const parts: string[] = [];

  if (request.conversationHistory) {
    parts.push(
      'You are continuing a previous conversation. Here is the history:',
      '',
      request.conversationHistory,
      '',
      `User's new message: ${request.prompt}`,
    );
  } else {
    parts.push(
      'You are an autonomous Claude Code agent executing a task.',
      `Working directory: ${request.workingDir || config.agent.workingDir}`,
      '',
      'IMPORTANT: Do NOT attempt to reply to Slack or use any Slack/MCP/notification tools.',
      'Do NOT use curl to post to any API. Just execute the task and print your result to stdout.',
      'Your stdout output will be captured and posted as a reply automatically.',
      '',
      'Task:',
      request.prompt,
      '',
      'Execute this task. Be concise — keep output under 3000 characters.',
    );
  }

  return parts.join('\n');
}

function runTask(request: TaskRequest): Promise<TaskResult> {
  const cwd = expandHome(request.workingDir || config.agent.workingDir);

  if (!fs.existsSync(cwd)) {
    return Promise.resolve({
      output: `Directory not found: \`${cwd}\`\nPlease check the path and try again.`,
      exitCode: 1,
      timedOut: false,
      durationMs: 0,
    });
  }

  const prompt = buildPrompt(request);
  const startTime = Date.now();

  currentTaskInfo = {
    threadTs: request.threadTs,
    channel: request.channel,
    startedAt: new Date().toISOString(),
  };

  return new Promise<TaskResult>((resolve) => {
    const args: string[] = ['-p', prompt, '--max-turns', String(config.agent.maxTurns), '--allowedTools', config.agent.allowedTools];

    if (config.agent.model) {
      args.push('--model', config.agent.model);
    }

    const child = execFile('claude', args, {
      cwd,
      timeout: config.agent.timeoutMs,
      maxBuffer: MAX_BUFFER,
      env: { ...process.env, DISABLE_INTERACTIVITY: '1' },
    }, (error, stdout, stderr) => {
      const durationMs = Date.now() - startTime;
      currentChild = null;
      currentTaskInfo = null;

      if (error) {
        logger.error(COMPONENT, 'Task failed', { error: error.message, durationMs });
        const output = stdout ? truncateForSlack(stdout) : `Task failed: ${error.message}`;
        const timedOut = error.message.includes('TIMEOUT') || error.killed === true;
        resolve({ output, exitCode: 1, timedOut, durationMs });
      } else {
        const output = truncateForSlack(stdout.trim() || '(no output)');
        resolve({ output, exitCode: 0, timedOut: false, durationMs });
      }
    });

    currentChild = child;
    if (child.stdin) child.stdin.end();
  });
}

export async function executeTask(request: TaskRequest): Promise<TaskResult> {
  return new Promise<TaskResult>((resolve) => {
    taskQueue.push({ request, resolve });
    processQueue();
  });
}

async function processQueue(): Promise<void> {
  if (isProcessing) return;
  isProcessing = true;

  while (taskQueue.length > 0) {
    const item = taskQueue.shift()!;
    try {
      const result = await runTask(item.request);
      item.resolve(result);
    } catch (err) {
      logger.error(COMPONENT, 'Unexpected error', { error: String(err) });
      item.resolve({
        output: `Internal error: ${String(err)}`,
        exitCode: 1,
        timedOut: false,
        durationMs: 0,
      });
    }
  }

  isProcessing = false;
}
