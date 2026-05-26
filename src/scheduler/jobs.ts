import { getBattery } from '../monitors/battery.js';
import { getDisk } from '../monitors/disk.js';
import { sendBlocks } from '../notifier/slack-sender.js';
import { formatAlert } from '../utils/format.js';
import { logger } from '../utils/logger.js';
import { config } from '../config.js';

// Track last alert state to avoid spamming
let lastBatteryAlert = false;
let lastDiskAlert = false;

export async function checkBattery(): Promise<void> {
  const battery = await getBattery();
  const isLow = battery.percent < config.thresholds.batteryLow && !battery.charging;

  if (isLow && !lastBatteryAlert) {
    // Transition: battery just became low
    logger.warn('scheduler', 'Battery low threshold triggered', {
      percent: battery.percent,
      threshold: config.thresholds.batteryLow,
    });

    const blocks = formatAlert(
      'Battery Low',
      `:battery: Battery is at *${battery.percent}%* and _not charging_.\n` +
        `Time remaining: ${battery.timeRemaining}\n` +
        `Threshold: ${config.thresholds.batteryLow}%`,
    );

    await sendBlocks(blocks);
    lastBatteryAlert = true;
  } else if (!isLow && lastBatteryAlert) {
    // Battery has recovered (either charged above threshold or now charging)
    logger.info('scheduler', 'Battery recovered', {
      percent: battery.percent,
      charging: battery.charging,
    });
    lastBatteryAlert = false;
  }
}

export async function checkDisk(): Promise<void> {
  const disk = await getDisk();
  const isHigh = disk.usedPercent > config.thresholds.diskUsageHigh;

  if (isHigh && !lastDiskAlert) {
    // Transition: disk usage just became high
    logger.warn('scheduler', 'Disk usage high threshold triggered', {
      usedPercent: disk.usedPercent,
      threshold: config.thresholds.diskUsageHigh,
    });

    const blocks = formatAlert(
      'Disk Usage High',
      `:floppy_disk: Disk usage is at *${disk.usedPercent}%*.\n` +
        `Used: ${disk.usedGB} / ${disk.sizeGB} (${disk.availGB} available)\n` +
        `Mount: ${disk.mountPoint}\n` +
        `Threshold: ${config.thresholds.diskUsageHigh}%`,
    );

    await sendBlocks(blocks);
    lastDiskAlert = true;
  } else if (!isHigh && lastDiskAlert) {
    // Disk usage has recovered
    logger.info('scheduler', 'Disk usage recovered', {
      usedPercent: disk.usedPercent,
    });
    lastDiskAlert = false;
  }
}

export async function runAllChecks(): Promise<void> {
  const results = await Promise.allSettled([checkBattery(), checkDisk()]);

  for (const result of results) {
    if (result.status === 'rejected') {
      logger.error('scheduler', 'Health check failed', {
        error: result.reason instanceof Error ? result.reason.message : String(result.reason),
      });
    }
  }
}
