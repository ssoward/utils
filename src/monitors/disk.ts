import type { DiskInfo } from '../types.js';
import { exec } from '../utils/exec.js';

/**
 * Parse macOS `df -h /` output to get root filesystem disk usage.
 *
 * Sample output:
 *   Filesystem        Size    Used   Avail Capacity iused ifree %iused  Mounted on
 *   /dev/disk3s1s1   926Gi    12Gi   412Gi     3%    458k  4.3G    0%   /
 *
 * Columns: Filesystem, Size, Used, Avail, Capacity, iused, ifree, %iused, Mounted on
 * We want columns 0 (filesystem), 1 (size), 2 (used), 3 (avail), 4 (capacity), and 8 (mount).
 */
export async function getDisk(): Promise<DiskInfo> {
  const output = await exec('df -h /');
  const lines = output.split('\n');

  // The data row is the second line (first is the header)
  const dataLine = lines[1];
  if (!dataLine) {
    throw new Error('Unexpected df output: no data line found');
  }

  // Split on whitespace. The "Mounted on" column may contain spaces,
  // but for root filesystem it is just "/".
  const parts = dataLine.trim().split(/\s+/);

  // Capacity is in the format "3%" -- extract the number
  const capacityMatch = parts[4]?.match(/(\d+)%/);
  const usedPercent = capacityMatch ? parseInt(capacityMatch[1], 10) : 0;

  return {
    filesystem: parts[0] ?? 'unknown',
    sizeGB: parts[1] ?? '0',
    usedGB: parts[2] ?? '0',
    availGB: parts[3] ?? '0',
    usedPercent,
    mountPoint: parts[8] ?? '/',
  };
}
