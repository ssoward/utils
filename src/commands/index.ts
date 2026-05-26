import type { App } from '@slack/bolt';
import statusCommand from './status.js';
import batteryCommand from './battery.js';
import diskCommand from './disk.js';
import cpuCommand from './cpu.js';
import memoryCommand from './memory.js';
import uptimeCommand from './uptime.js';
import runCommand from './run.js';
import notifyCommand from './notify.js';
import claudeCommand from './claude.js';
import { logger } from '../utils/logger.js';

export function registerCommands(app: App): void {
  app.command('/status', statusCommand);
  app.command('/battery', batteryCommand);
  app.command('/disk', diskCommand);
  app.command('/cpu', cpuCommand);
  app.command('/memory', memoryCommand);
  app.command('/uptime', uptimeCommand);
  app.command('/run', runCommand);
  app.command('/notify', notifyCommand);
  app.command('/claude', claudeCommand);

  logger.info('commands', 'All slash commands registered');
}
