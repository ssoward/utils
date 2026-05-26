import { WebSocketServer, WebSocket } from 'ws';
import type http from 'node:http';
import { logger } from '../utils/logger.js';
import { isSessionActive, touchSession } from '../session-registry/index.js';
import type { SlackIncomingMessage } from '../types.js';

const COMPONENT = 'ws-bridge';
const HEARTBEAT_INTERVAL_MS = 30_000;

interface ClientEntry {
  ws: WebSocket;
  sessionId: string;
  alive: boolean;
}

const clients: Map<string, ClientEntry> = new Map();
let wss: WebSocketServer | null = null;
let heartbeatTimer: ReturnType<typeof setInterval> | null = null;

/**
 * Create a WebSocket server and attach it to upgrade events for the /ws path.
 * Clients connect with ?session_id=cc-XXXX query param.
 */
export function createWebSocketServer(server: http.Server): WebSocketServer {
  wss = new WebSocketServer({ noServer: true });

  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url || '/', 'http://localhost');
    if (url.pathname !== '/ws') {
      socket.destroy();
      return;
    }

    const sessionId = url.searchParams.get('session_id');
    if (!sessionId) {
      logger.warn(COMPONENT, 'WebSocket upgrade rejected: missing session_id');
      socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
      socket.destroy();
      return;
    }

    if (!isSessionActive(sessionId)) {
      logger.warn(COMPONENT, 'WebSocket upgrade rejected: unknown session', { sessionId });
      socket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
      socket.destroy();
      return;
    }

    wss!.handleUpgrade(req, socket, head, (ws) => {
      wss!.emit('connection', ws, req, sessionId);
    });
  });

  wss.on('connection', (ws: WebSocket, _req: http.IncomingMessage, sessionId: string) => {
    // Close existing connection for this session (replace)
    const existing = clients.get(sessionId);
    if (existing) {
      logger.info(COMPONENT, 'Replacing existing WebSocket connection', { sessionId });
      existing.ws.close(1000, 'replaced');
    }

    const entry: ClientEntry = { ws, sessionId, alive: true };
    clients.set(sessionId, entry);
    touchSession(sessionId);
    logger.info(COMPONENT, 'WebSocket client connected', { sessionId, totalClients: clients.size });

    ws.on('pong', () => {
      entry.alive = true;
    });

    ws.on('close', () => {
      // Only remove if this is still the current connection for this session
      if (clients.get(sessionId) === entry) {
        clients.delete(sessionId);
        logger.info(COMPONENT, 'WebSocket client disconnected', { sessionId, totalClients: clients.size });
      }
    });

    ws.on('error', (err) => {
      logger.error(COMPONENT, 'WebSocket error', { sessionId, error: String(err) });
    });
  });

  // Start heartbeat
  heartbeatTimer = setInterval(() => {
    for (const [sessionId, entry] of clients) {
      if (!entry.alive) {
        logger.info(COMPONENT, 'Terminating dead WebSocket connection', { sessionId });
        entry.ws.terminate();
        clients.delete(sessionId);
        continue;
      }
      entry.alive = false;
      entry.ws.ping();
    }
  }, HEARTBEAT_INTERVAL_MS);

  return wss;
}

/**
 * Push a message to connected WebSocket clients.
 * If the message has a targetSession, send only to that client.
 * Otherwise, broadcast to all connected clients.
 */
export function pushToClients(msg: SlackIncomingMessage): void {
  if (clients.size === 0) return;

  const payload = JSON.stringify({ type: 'message', message: msg });

  if (msg.targetSession) {
    const entry = clients.get(msg.targetSession);
    if (entry && entry.ws.readyState === WebSocket.OPEN) {
      entry.ws.send(payload);
      logger.info(COMPONENT, 'Pushed message to session', { sessionId: msg.targetSession, msgId: msg.id });
    }
    // Also push to dashboard sessions (dash-*) so they can monitor all traffic
    for (const [sessionId, dashEntry] of clients) {
      if (sessionId.startsWith('dash-') && dashEntry.ws.readyState === WebSocket.OPEN) {
        dashEntry.ws.send(payload);
        logger.info(COMPONENT, 'Also pushed to dashboard', { sessionId, msgId: msg.id });
      }
    }
  } else {
    // Broadcast to all connected clients
    let sent = 0;
    for (const [, entry] of clients) {
      if (entry.ws.readyState === WebSocket.OPEN) {
        entry.ws.send(payload);
        sent++;
      }
    }
    if (sent > 0) {
      logger.info(COMPONENT, 'Broadcast message to clients', { msgId: msg.id, clientCount: sent });
    }
  }
}

/**
 * Check if a session has an active WebSocket connection.
 */
export function isWsConnected(sessionId: string): boolean {
  const entry = clients.get(sessionId);
  return !!entry && entry.ws.readyState === WebSocket.OPEN;
}

/**
 * Get the number of connected WebSocket clients.
 */
export function getConnectedClientCount(): number {
  return clients.size;
}

/**
 * Shut down the WebSocket server and clean up.
 */
export function closeWebSocketServer(): void {
  if (heartbeatTimer) {
    clearInterval(heartbeatTimer);
    heartbeatTimer = null;
  }
  for (const [, entry] of clients) {
    entry.ws.close(1000, 'server shutdown');
  }
  clients.clear();
  if (wss) {
    wss.close();
    wss = null;
  }
}

// Exported for testing
export function _getClients(): Map<string, ClientEntry> {
  return clients;
}
