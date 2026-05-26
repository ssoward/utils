import { runAllChecks } from './jobs.js';
import { logger } from '../utils/logger.js';

let intervalId: ReturnType<typeof setInterval> | null = null;

export function startScheduler(intervalMinutes: number): void {
  if (intervalId) {
    logger.warn('scheduler', 'Scheduler already running; stopping previous instance');
    stopScheduler();
  }

  logger.info('scheduler', `Scheduler started with ${intervalMinutes}-minute interval`);

  // Run checks immediately on start
  runAllChecks();

  // Then set recurring interval
  const intervalMs = intervalMinutes * 60 * 1000;
  intervalId = setInterval(() => {
    runAllChecks();
  }, intervalMs);
}

export function stopScheduler(): void {
  if (intervalId) {
    clearInterval(intervalId);
    intervalId = null;
    logger.info('scheduler', 'Scheduler stopped');
  }
}
