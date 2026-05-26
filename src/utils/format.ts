import type { KnownBlock } from '@slack/types';
import type { SystemStatus, BatteryInfo, CpuInfo, MemoryInfo, DiskInfo } from '../types.js';

type Block = KnownBlock;

function section(text: string): Block {
  return { type: 'section', text: { type: 'mrkdwn', text } } as Block;
}

function divider(): Block {
  return { type: 'divider' } as Block;
}

function header(text: string): Block {
  return { type: 'header', text: { type: 'plain_text', text, emoji: true } } as Block;
}

function progressBar(percent: number, width = 10): string {
  const filled = Math.round((percent / 100) * width);
  const empty = width - filled;
  return '\u2588'.repeat(filled) + '\u2591'.repeat(empty);
}

export function formatBattery(battery: BatteryInfo): Block[] {
  const icon = battery.charging ? ':electric_plug:' : ':battery:';
  const status = battery.charging ? 'Charging' : 'On Battery';
  return [
    header('Battery'),
    section(
      `${icon} *${battery.percent}%* \`${progressBar(battery.percent)}\`\n` +
      `Status: ${status} (${battery.source})\n` +
      `Time remaining: ${battery.timeRemaining}`
    ),
  ];
}

export function formatCpu(cpu: CpuInfo): Block[] {
  const usage = cpu.userPercent + cpu.systemPercent;
  return [
    header('CPU'),
    section(
      `:gear: *Usage: ${usage.toFixed(1)}%* \`${progressBar(usage)}\`\n` +
      `User: ${cpu.userPercent.toFixed(1)}% | System: ${cpu.systemPercent.toFixed(1)}% | Idle: ${cpu.idlePercent.toFixed(1)}%\n` +
      `Load avg: ${cpu.loadAvg.join(', ')}`
    ),
  ];
}

export function formatMemory(memory: MemoryInfo): Block[] {
  return [
    header('Memory'),
    section(
      `:brain: *${memory.usedPercent.toFixed(1)}% used* \`${progressBar(memory.usedPercent)}\`\n` +
      `${memory.usedGB.toFixed(1)} GB / ${memory.totalGB.toFixed(1)} GB (${memory.freeGB.toFixed(1)} GB free)`
    ),
  ];
}

export function formatDisk(disk: DiskInfo): Block[] {
  return [
    header('Disk'),
    section(
      `:floppy_disk: *${disk.usedPercent}% used* \`${progressBar(disk.usedPercent)}\`\n` +
      `${disk.usedGB} / ${disk.sizeGB} (${disk.availGB} available)\n` +
      `Mount: ${disk.mountPoint}`
    ),
  ];
}

export function formatFullStatus(status: SystemStatus): Block[] {
  const cpuUsage = status.cpu.userPercent + status.cpu.systemPercent;
  return [
    header(`System Status: ${status.hostname}`),
    section(`:clock1: ${status.timestamp} | Uptime: ${status.uptime}`),
    divider(),
    ...formatCpu(status.cpu),
    divider(),
    ...formatMemory(status.memory),
    divider(),
    ...formatDisk(status.disk),
    divider(),
    ...formatBattery(status.battery),
  ];
}

export function formatAlert(title: string, message: string): Block[] {
  return [
    header(`:warning: Alert: ${title}`),
    section(message),
  ];
}

export function formatNotification(title: string, message: string): Block[] {
  return [
    header(title || 'Notification'),
    section(message),
  ];
}
