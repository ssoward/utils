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

// --- Agent types ---

export interface TaskRequest {
  prompt: string;
  workingDir?: string;
  conversationHistory?: string;
  threadTs: string;
  channel: string;
  messageTs: string;
  userId: string;
}

export interface TaskResult {
  output: string;
  exitCode: number;
  timedOut: boolean;
  durationMs: number;
}

export interface AgentSession {
  threadTs: string;
  channel: string;
  createdAt: string;
  lastActiveAt: string;
  workingDir: string;
  exchanges: AgentExchange[];
}

export interface AgentExchange {
  role: 'user' | 'agent';
  content: string;
  timestamp: string;
}
