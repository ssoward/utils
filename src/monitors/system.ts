import type { CpuInfo, MemoryInfo } from '../types.js';
import { exec } from '../utils/exec.js';

/**
 * Collect CPU usage percentages from `top` and load averages from `sysctl`.
 *
 * `top -l 1 -n 0 -s 0` sample line:
 *   CPU usage: 24.20% user, 14.22% sys, 61.57% idle
 *
 * `sysctl -n vm.loadavg` sample:
 *   { 5.69 5.37 4.37 }
 */
export async function getCpu(): Promise<CpuInfo> {
  const [topOutput, loadOutput] = await Promise.all([
    exec('top -l 1 -n 0 -s 0'),
    exec('sysctl -n vm.loadavg'),
  ]);

  // Parse CPU usage line
  let userPercent = 0;
  let systemPercent = 0;
  let idlePercent = 0;

  const cpuLine = topOutput
    .split('\n')
    .find((line) => line.startsWith('CPU usage:'));

  if (cpuLine) {
    const userMatch = cpuLine.match(/([\d.]+)%\s*user/);
    const sysMatch = cpuLine.match(/([\d.]+)%\s*sys/);
    const idleMatch = cpuLine.match(/([\d.]+)%\s*idle/);

    if (userMatch) userPercent = parseFloat(userMatch[1]);
    if (sysMatch) systemPercent = parseFloat(sysMatch[1]);
    if (idleMatch) idlePercent = parseFloat(idleMatch[1]);
  }

  // Parse load averages from "{ 5.69 5.37 4.37 }"
  const loadAvg: [number, number, number] = [0, 0, 0];
  const loadMatch = loadOutput.match(
    /\{\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\}/,
  );

  if (loadMatch) {
    loadAvg[0] = parseFloat(loadMatch[1]);
    loadAvg[1] = parseFloat(loadMatch[2]);
    loadAvg[2] = parseFloat(loadMatch[3]);
  }

  return { userPercent, systemPercent, idlePercent, loadAvg };
}

const BYTES_PER_GB = 1024 * 1024 * 1024;

/**
 * Collect memory information from `sysctl` and `vm_stat`.
 *
 * `sysctl -n hw.memsize` returns total physical memory in bytes.
 *
 * `vm_stat` returns page-based statistics. The first line contains the page
 * size, and subsequent lines contain named counters. We compute used memory
 * as (active + wired + compressor) pages and free as total minus used.
 *
 * Sample vm_stat header:
 *   Mach Virtual Memory Statistics: (page size of 16384 bytes)
 */
export async function getMemory(): Promise<MemoryInfo> {
  const [memsizeStr, vmstatOutput] = await Promise.all([
    exec('sysctl -n hw.memsize'),
    exec('vm_stat'),
  ]);

  const totalBytes = parseInt(memsizeStr, 10);
  const totalGB = parseFloat((totalBytes / BYTES_PER_GB).toFixed(2));

  // Extract page size from the header line
  const pageSizeMatch = vmstatOutput.match(/page size of (\d+) bytes/);
  const pageSize = pageSizeMatch ? parseInt(pageSizeMatch[1], 10) : 16384;

  // Helper to extract a page count by name
  const getPages = (name: string): number => {
    const regex = new RegExp(`^${name}:\\s+(\\d+)`, 'm');
    const match = vmstatOutput.match(regex);
    return match ? parseInt(match[1], 10) : 0;
  };

  const active = getPages('Pages active');
  const wired = getPages('Pages wired down');
  const compressor = getPages('Pages occupied by compressor');
  const speculative = getPages('Pages speculative');
  const free = getPages('Pages free');
  const inactive = getPages('Pages inactive');

  // Used = active + wired + compressor (pages actively consumed)
  const usedBytes = (active + wired + compressor) * pageSize;
  // Free = free + inactive + speculative (pages available for use)
  const freeBytes = (free + inactive + speculative) * pageSize;

  // Prefer sysctl total; derive the other value to keep consistency
  const usedGB = parseFloat((usedBytes / BYTES_PER_GB).toFixed(2));
  const freeGB = parseFloat((freeBytes / BYTES_PER_GB).toFixed(2));
  const usedPercent = parseFloat(((usedBytes / totalBytes) * 100).toFixed(1));

  return { totalGB, usedGB, freeGB, usedPercent };
}

/**
 * Get system uptime string.
 *
 * `uptime` sample:
 *   12:32  up  3:32, 3 users, load averages: 5.72 5.38 4.38
 *   12:32  up 1 day, 5:32, 3 users, load averages: ...
 */
export async function getUptime(): Promise<string> {
  const output = await exec('uptime');

  // Extract everything between "up " and the first ", N user" segment
  const match = output.match(/up\s+(.+?),\s+\d+ users?/);
  return match ? match[1].trim() : output;
}
