#!/usr/bin/env node

// ChromeCC Native Messaging Host
// Bridges Chrome extension <-> claude CLI via Chrome Native Messaging protocol
//
// Protocol: Messages are framed with a 4-byte little-endian length prefix followed
// by UTF-8 JSON. Both reads (stdin) and writes (stdout) use this framing.

const { spawn, execSync } = require('child_process');
const path = require('path');

// Resolve the full path to claude CLI at startup.
// Chrome launches native hosts with a minimal PATH that won't include
// /opt/homebrew/bin or other user-installed locations.
let claudePath = 'claude';
try {
  // Try common locations first, then fall back to shell resolution
  const candidates = [
    '/opt/homebrew/bin/claude',
    '/usr/local/bin/claude',
    path.join(process.env.HOME || '', '.npm-global/bin/claude'),
  ];
  const fs = require('fs');
  for (const p of candidates) {
    try {
      fs.accessSync(p, fs.constants.X_OK);
      claudePath = p;
      break;
    } catch { /* not found, try next */ }
  }
  // If none of the candidates worked, try shell resolution
  if (claudePath === 'claude') {
    claudePath = execSync('which claude 2>/dev/null || echo claude', { encoding: 'utf8' }).trim();
  }
} catch {
  // Fall through with 'claude' — will get ENOENT error with a clear message
}

function readMessage() {
  return new Promise((resolve, reject) => {
    const headerBuf = Buffer.alloc(4);
    let headerBytesRead = 0;

    function onReadable() {
      while (headerBytesRead < 4) {
        const chunk = process.stdin.read(4 - headerBytesRead);
        if (chunk === null) return;
        chunk.copy(headerBuf, headerBytesRead);
        headerBytesRead += chunk.length;
      }

      process.stdin.removeListener('readable', onReadable);
      const msgLen = headerBuf.readUInt32LE(0);

      if (msgLen === 0) {
        resolve(null);
        return;
      }

      let body = Buffer.alloc(0);
      function onBodyReadable() {
        while (body.length < msgLen) {
          const remaining = msgLen - body.length;
          const chunk = process.stdin.read(remaining);
          if (chunk === null) return;
          body = Buffer.concat([body, chunk]);
        }
        process.stdin.removeListener('readable', onBodyReadable);
        try {
          resolve(JSON.parse(body.toString('utf8')));
        } catch (e) {
          reject(new Error('Invalid JSON: ' + e.message));
        }
      }

      process.stdin.on('readable', onBodyReadable);
      onBodyReadable();
    }

    process.stdin.on('readable', onReadable);
    onReadable();
  });
}

function writeMessage(msg) {
  const json = JSON.stringify(msg);
  const buf = Buffer.from(json, 'utf8');
  const header = Buffer.alloc(4);
  header.writeUInt32LE(buf.length, 0);
  process.stdout.write(header);
  process.stdout.write(buf);
}

function handlePrompt(prompt) {
  return new Promise((resolve) => {
    const args = ['-p', '--output-format', 'stream-json', '--verbose', prompt];

    const child = spawn(claudePath, args, {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env }
    });

    let buffer = '';
    let sentAnyChunks = false;
    let hadError = false;

    child.stdout.on('data', (data) => {
      buffer += data.toString();
      const lines = buffer.split('\n');
      buffer = lines.pop();

      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const event = JSON.parse(line);
          if (event.type === 'assistant' && event.message?.content) {
            for (const block of event.message.content) {
              if (block.type === 'text' && block.text) {
                sentAnyChunks = true;
                writeMessage({ type: 'chunk', text: block.text });
              }
            }
          }
          if (event.type === 'result' && event.result && !sentAnyChunks) {
            writeMessage({ type: 'chunk', text: event.result });
          }
        } catch {
          // Not JSON or irrelevant line
        }
      }
    });

    child.stderr.on('data', (data) => {
      process.stderr.write(data);
    });

    child.on('error', (err) => {
      hadError = true;
      let errorMsg = 'Something went wrong. Try again.';
      if (err.code === 'ENOENT') {
        errorMsg = 'Claude CLI not found. Install Claude Code first.';
      }
      writeMessage({ type: 'error', error: errorMsg });
      resolve();
    });

    child.on('close', (code) => {
      if (hadError) {
        resolve();
        return;
      }
      if (code !== 0 && code !== null) {
        writeMessage({ type: 'error', error: 'Claude exited with an error. Check your login with `claude` in the terminal.' });
      }
      writeMessage({ type: 'done' });
      resolve();
    });
  });
}

async function main() {
  while (true) {
    try {
      const message = await readMessage();
      if (message === null) {
        process.exit(0);
      }
      if (message.type === 'prompt') {
        await handlePrompt(message.prompt);
      }
    } catch (e) {
      writeMessage({ type: 'error', error: e.message });
      process.exit(1);
    }
  }
}

main();
