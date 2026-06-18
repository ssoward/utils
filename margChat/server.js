import express from 'express';
import http from 'node:http';
import { Server as IOServer } from 'socket.io';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createStore } from './src/store.js';
import { registerHandlers } from './src/handlers.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const app = express();
app.use(express.static(path.join(__dirname, 'public')));

const httpServer = http.createServer(app);

// Allowed Socket.IO origins. Default '*' keeps tunnel-sharing easy.
// For local-only use, set ALLOWED_ORIGINS=http://localhost:3000 (comma-separated for multiple).
const allowedOrigins = (process.env.ALLOWED_ORIGINS || '*')
  .split(',')
  .map(s => s.trim())
  .filter(Boolean);
const corsOrigin = allowedOrigins.length === 1 && allowedOrigins[0] === '*'
  ? '*'
  : allowedOrigins;
const io = new IOServer(httpServer, { cors: { origin: corsOrigin } });

const store = createStore();
registerHandlers(io, store);

const port = Number(process.env.PORT) || 3000;
httpServer.listen(port, () => {
  console.log(`margChat listening on http://localhost:${port}`);
});
