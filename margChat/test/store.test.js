import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createStore } from '../src/store.js';

test('new store has a lobby room with no users', () => {
  const store = createStore();
  const state = store.getRoomState('lobby');
  assert.equal(state.room, 'lobby');
  assert.deepEqual(state.users, []);
  assert.deepEqual(state.recentMessages, []);
  assert.deepEqual(state.rooms, ['lobby']);
});

test('joinRoom places user in lobby and returns user', () => {
  const store = createStore();
  const user = store.joinRoom('sock1', 'alice');
  assert.equal(user.username, 'alice');
  assert.equal(user.currentRoom, 'lobby');
  const state = store.getRoomState('lobby');
  assert.deepEqual(state.users, ['alice']);
});

test('joinRoom rejects duplicate username (server-wide)', () => {
  const store = createStore();
  store.joinRoom('sock1', 'alice');
  assert.throws(() => store.joinRoom('sock2', 'alice'), /USERNAME_TAKEN/);
});

test('addMessage appends a message visible in recentMessages', () => {
  const store = createStore();
  store.joinRoom('sock1', 'alice');
  const msg = store.addMessage('sock1', 'hello');
  assert.equal(msg.from, 'alice');
  assert.equal(msg.text, 'hello');
  assert.equal(typeof msg.ts, 'number');
  const state = store.getRoomState('lobby');
  assert.equal(state.recentMessages.length, 1);
  assert.equal(state.recentMessages[0].text, 'hello');
});

test('ring buffer keeps only the last 50 messages', () => {
  const store = createStore();
  store.joinRoom('sock1', 'alice');
  for (let i = 0; i < 60; i++) {
    store.addMessage('sock1', `msg-${i}`);
  }
  const state = store.getRoomState('lobby');
  assert.equal(state.recentMessages.length, 50);
  assert.equal(state.recentMessages[0].text, 'msg-10');
  assert.equal(state.recentMessages[49].text, 'msg-59');
});

test('addMessage throws if socketId is unknown', () => {
  const store = createStore();
  assert.throws(() => store.addMessage('ghost', 'hi'), /NO_USER/);
});

test('switchRoom moves user, auto-creates target room', () => {
  const store = createStore();
  store.joinRoom('sock1', 'alice');
  store.switchRoom('sock1', 'alpha');
  const alphaState = store.getRoomState('alpha');
  assert.deepEqual(alphaState.users, ['alice']);
  const lobbyState = store.getRoomState('lobby');
  assert.deepEqual(lobbyState.users, []);
});

test('switchRoom GCs empty non-lobby rooms', () => {
  const store = createStore();
  store.joinRoom('sock1', 'alice');
  store.switchRoom('sock1', 'alpha');
  store.switchRoom('sock1', 'beta');
  const lobbyState = store.getRoomState('lobby');
  assert.deepEqual(lobbyState.rooms.sort(), ['beta', 'lobby']);
});

test('lobby is never garbage-collected even when empty', () => {
  const store = createStore();
  store.joinRoom('sock1', 'alice');
  store.switchRoom('sock1', 'alpha');
  const state = store.getRoomState('alpha');
  assert.ok(state.rooms.includes('lobby'));
});

test('removeUser removes from current room and from users map', () => {
  const store = createStore();
  store.joinRoom('sock1', 'alice');
  store.joinRoom('sock2', 'bob');
  const removed = store.removeUser('sock1');
  assert.equal(removed.username, 'alice');
  const state = store.getRoomState('lobby');
  assert.deepEqual(state.users, ['bob']);
});

test('removeUser is a no-op if socketId unknown', () => {
  const store = createStore();
  assert.doesNotThrow(() => store.removeUser('ghost'));
});

test('removeUser GCs empty non-lobby rooms', () => {
  const store = createStore();
  store.joinRoom('sock1', 'alice');
  store.switchRoom('sock1', 'alpha');
  store.removeUser('sock1');
  const state = store.getRoomState('lobby');
  assert.ok(!state.rooms.includes('alpha'));
});

test('getUsername returns username for known socketId, undefined otherwise', () => {
  const store = createStore();
  store.joinRoom('sock1', 'alice');
  assert.equal(store.getUsername('sock1'), 'alice');
  assert.equal(store.getUsername('ghost'), undefined);
});
