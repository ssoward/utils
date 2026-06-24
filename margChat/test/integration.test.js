import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import express from 'express';
import { Server as IOServer } from 'socket.io';
import { io as ioClient } from 'socket.io-client';
import { createStore } from '../src/store.js';
import { registerHandlers } from '../src/handlers.js';

function bootServer() {
  const app = express();
  const httpServer = http.createServer(app);
  const io = new IOServer(httpServer);
  const store = createStore();
  registerHandlers(io, store);
  return new Promise((resolve) => {
    httpServer.listen(0, () => {
      const { port } = httpServer.address();
      resolve({ url: `http://localhost:${port}`, httpServer, io });
    });
  });
}

function connect(url) {
  return new Promise((resolve) => {
    const c = ioClient(url, { transports: ['websocket'], forceNew: true });
    c.on('connect', () => resolve(c));
  });
}

function once(client, event) {
  return new Promise((resolve) => client.once(event, resolve));
}

test('join returns roomState placing user in lobby', async () => {
  const { url, httpServer, io } = await bootServer();
  const client = await connect(url);
  const stateP = once(client, 'roomState');
  client.emit('join', { username: 'alice' });
  const state = await stateP;
  assert.equal(state.room, 'lobby');
  assert.deepEqual(state.users, ['alice']);
  client.close();
  io.close();
  httpServer.close();
});

test('join with taken username emits errorMsg', async () => {
  const { url, httpServer, io } = await bootServer();
  const a = await connect(url);
  const b = await connect(url);
  const stateP = once(a, 'roomState');
  a.emit('join', { username: 'alice' });
  await stateP;
  const errP = once(b, 'errorMsg');
  b.emit('join', { username: 'alice' });
  const err = await errP;
  assert.equal(err.code, 'USERNAME_TAKEN');
  a.close();
  b.close();
  io.close();
  httpServer.close();
});

test('sendMessage broadcasts to other clients in same room', async () => {
  const { url, httpServer, io } = await bootServer();
  const a = await connect(url);
  const b = await connect(url);
  a.emit('join', { username: 'alice' });
  await once(a, 'roomState');
  b.emit('join', { username: 'bob' });
  await once(b, 'roomState');
  const msgP = once(b, 'message');
  a.emit('sendMessage', { text: 'hello bob' });
  const msg = await msgP;
  assert.equal(msg.from, 'alice');
  assert.equal(msg.text, 'hello bob');
  a.close();
  b.close();
  io.close();
  httpServer.close();
});

test('sendMessage with empty text emits errorMsg', async () => {
  const { url, httpServer, io } = await bootServer();
  const a = await connect(url);
  a.emit('join', { username: 'alice' });
  await once(a, 'roomState');
  const errP = once(a, 'errorMsg');
  a.emit('sendMessage', { text: '   ' });
  const err = await errP;
  assert.equal(err.code, 'MESSAGE_INVALID');
  a.close();
  io.close();
  httpServer.close();
});

test('switchRoom moves user and isolates messages', async () => {
  const { url, httpServer, io } = await bootServer();
  const a = await connect(url);
  const b = await connect(url);
  a.emit('join', { username: 'alice' });
  await once(a, 'roomState');
  b.emit('join', { username: 'bob' });
  await once(b, 'roomState');
  const aState = once(a, 'roomState');
  a.emit('switchRoom', { room: 'alpha' });
  const moved = await aState;
  assert.equal(moved.room, 'alpha');
  // Alice sends in alpha; bob (in lobby) should not receive it.
  let bobGotIt = false;
  b.on('message', () => { bobGotIt = true; });
  a.emit('sendMessage', { text: 'in alpha' });
  await new Promise(r => setTimeout(r, 50));
  assert.equal(bobGotIt, false);
  a.close();
  b.close();
  io.close();
  httpServer.close();
});

test('typing event is broadcast to others in same room', async () => {
  const { url, httpServer, io } = await bootServer();
  const a = await connect(url);
  const b = await connect(url);
  a.emit('join', { username: 'alice' });
  await once(a, 'roomState');
  b.emit('join', { username: 'bob' });
  await once(b, 'roomState');
  const t = once(b, 'typing');
  a.emit('typing', { isTyping: true });
  const evt = await t;
  assert.equal(evt.username, 'alice');
  assert.equal(evt.isTyping, true);
  a.close();
  b.close();
  io.close();
  httpServer.close();
});
