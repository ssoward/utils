import type { BatteryInfo } from '../types.js';
import { exec } from '../utils/exec.js';

/**
 * Parse macOS `pmset -g batt` output to extract battery information.
 *
 * Example outputs:
 *   Now drawing from 'AC Power'
 *    -InternalBattery-0 (id=22806627)	100%; charged; 0:00 remaining present: true
 *
 *   Now drawing from 'Battery Power'
 *    -InternalBattery-0 (id=22806627)	72%; discharging; 3:45 remaining present: true
 *
 *   Now drawing from 'AC Power'
 *    -InternalBattery-0 (id=22806627)	85%; charging; 1:20 remaining present: true
 *
 * Desktop Macs (no battery):
 *   Now drawing from 'AC Power'
 *   (no additional lines)
 */
export async function getBattery(): Promise<BatteryInfo> {
  const output = await exec('pmset -g batt');
  const lines = output.split('\n');

  // Extract power source from the first line
  const sourceMatch = lines[0]?.match(/Now drawing from '([^']+)'/);
  const source = sourceMatch ? sourceMatch[1] : 'Unknown';

  // If there is no battery line (desktop Mac), return defaults
  const batteryLine = lines.find((line) => line.includes('InternalBattery'));
  if (!batteryLine) {
    return {
      percent: 100,
      charging: false,
      timeRemaining: 'N/A (No battery)',
      source,
    };
  }

  // Extract percentage: look for a number followed by %
  const percentMatch = batteryLine.match(/(\d+)%/);
  const percent = percentMatch ? parseInt(percentMatch[1], 10) : 0;

  // Extract charging status from the state keyword after the percentage
  // Possible states: charging, discharging, charged, finishing charge, (no estimate)
  const isCharging =
    batteryLine.includes('charging') && !batteryLine.includes('discharging');

  // Extract time remaining: pattern like "3:45 remaining" or "0:00 remaining"
  const timeMatch = batteryLine.match(/(\d+:\d+) remaining/);
  let timeRemaining: string;

  if (timeMatch) {
    timeRemaining = timeMatch[1];
  } else if (batteryLine.includes('charged')) {
    timeRemaining = 'Fully charged';
  } else if (batteryLine.includes('(no estimate)') || batteryLine.includes('not charging')) {
    timeRemaining = 'Calculating...';
  } else {
    timeRemaining = 'Unknown';
  }

  return {
    percent,
    charging: isCharging,
    timeRemaining,
    source,
  };
}
