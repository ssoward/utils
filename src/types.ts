export interface SystemStatus {
  cpu: CpuInfo;
  memory: MemoryInfo;
  disk: DiskInfo;
  battery: BatteryInfo;
  uptime: string;
  hostname: string;
  timestamp: string;
}

export interface CpuInfo {
  userPercent: number;
  systemPercent: number;
  idlePercent: number;
  loadAvg: [number, number, number];
}

export interface MemoryInfo {
  totalGB: number;
  usedGB: number;
  freeGB: number;
  usedPercent: number;
}

export interface DiskInfo {
  filesystem: string;
  sizeGB: string;
  usedGB: string;
  availGB: string;
  usedPercent: number;
  mountPoint: string;
}

export interface BatteryInfo {
  percent: number;
  charging: boolean;
  timeRemaining: string;
  source: string;
}

export interface ClaudeHookEvent {
  type: string;
  sessionId?: string;
  message?: string;
  timestamp: string;
  [key: string]: unknown;
}

export interface NotifyPayload {
  message: string;
  channel?: string;
  title?: string;
  sessionId?: string;
}

export interface SlackIncomingMessage {
  id: string;
  source: 'dm' | 'mention';
  text: string;
  userId: string;
  channel: string;
  threadTs?: string;
  messageTs: string;
  receivedAt: string;
  read: boolean;
  targetSession?: string;
}

export interface MessageQueueFile {
  version: number;
  lastUpdated: string;
  messages: SlackIncomingMessage[];
}

export interface SessionInfo {
  id: string;
  termSessionId?: string;
  registeredAt: string;
  lastSeenAt: string;
  label?: string;
  wsConnected?: boolean;
}

export interface SessionRegistryFile {
  version: number;
  lastUpdated: string;
  sessions: SessionInfo[];
}

export interface ReplyPayload {
  channel: string;
  text: string;
  threadTs?: string;
  blocks?: unknown[];
}
