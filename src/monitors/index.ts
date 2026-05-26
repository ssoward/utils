import os from 'node:os';
import type { SystemStatus } from '../types.js';
import { getBattery } from './battery.js';
import { getDisk } from './disk.js';
import { getCpu, getMemory, getUptime } from './system.js';

export { getBattery } from './battery.js';
export { getDisk } from './disk.js';
export { getCpu, getMemory, getUptime } from './system.js';

/**
 * Collect full system status by running all monitors in parallel.
 */
export async function getFullStatus(): Promise<SystemStatus> {
  const [cpu, memory, disk, battery, uptime] = await Promise.all([
    getCpu(),
    getMemory(),
    getDisk(),
    getBattery(),
    getUptime(),
  ]);

  return {
    cpu,
    memory,
    disk,
    battery,
    uptime,
    hostname: os.hostname(),
    timestamp: new Date().toISOString(),
  };
}
