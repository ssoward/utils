const USERNAME_RE = /^[a-zA-Z0-9_\- ]{1,24}$/;
const ROOM_RE = /^[a-zA-Z0-9_\- ]{1,32}$/;

const RATE_LIMIT_MAX = 5;
const RATE_LIMIT_WINDOW_MS = 2000;

function makeRateLimiter() {
  const log = []; // timestamps
  return function allow() {
    const now = Date.now();
    while (log.length && now - log[0] > RATE_LIMIT_WINDOW_MS) log.shift();
    if (log.length >= RATE_LIMIT_MAX) return false;
    log.push(now);
    return true;
  };
}

function emitError(socket, code, message) {
  socket.emit('errorMsg', { code, message });
}

export function registerHandlers(io, store) {
  io.on('connection', (socket) => {
    const allowSend = makeRateLimiter();

    socket.on('join', ({ username } = {}) => {
      const name = typeof username === 'string' ? username.trim() : '';
      if (!USERNAME_RE.test(name)) {
        return emitError(socket, 'USERNAME_INVALID', 'Username must be 1-24 chars, letters/numbers/_-/space.');
      }
      try {
        store.joinRoom(socket.id, name, 'lobby');
      } catch (e) {
        if (e.message === 'USERNAME_TAKEN') {
          return emitError(socket, 'USERNAME_TAKEN', 'That username is already in use.');
        }
        return emitError(socket, 'INTERNAL', 'Server error.');
      }
      socket.join('lobby');
      socket.to('lobby').emit('userJoined', { username: name });
      socket.emit('roomState', store.getRoomState('lobby'));
    });

    socket.on('sendMessage', ({ text } = {}) => {
      const body = typeof text === 'string' ? text.trim() : '';
      if (body.length < 1 || body.length > 2000) {
        return emitError(socket, 'MESSAGE_INVALID', 'Message must be 1-2000 chars.');
      }
      if (!allowSend()) {
        return emitError(socket, 'RATE_LIMITED', 'Slow down.');
      }
      let msg;
      try {
        msg = store.addMessage(socket.id, body);
      } catch {
        return emitError(socket, 'NOT_JOINED', 'Join before sending messages.');
      }
      const currentRoom = [...socket.rooms].find(r => r !== socket.id);
      io.to(currentRoom).emit('message', msg);
    });

    socket.on('switchRoom', ({ room } = {}) => {
      const target = typeof room === 'string' ? room.trim() : '';
      if (!ROOM_RE.test(target)) {
        return emitError(socket, 'ROOM_INVALID', 'Room name must be 1-32 chars, letters/numbers/_-/space.');
      }
      const username = store.getUsername(socket.id);
      if (!username) return emitError(socket, 'NOT_JOINED', 'Join before switching rooms.');
      const prevRoom = [...socket.rooms].find(r => r !== socket.id);
      try {
        store.switchRoom(socket.id, target);
      } catch {
        return emitError(socket, 'INTERNAL', 'Server error.');
      }
      if (prevRoom) {
        socket.leave(prevRoom);
        socket.to(prevRoom).emit('userLeft', { username });
      }
      socket.join(target);
      socket.to(target).emit('userJoined', { username });
      socket.emit('roomState', store.getRoomState(target));
    });

    socket.on('typing', ({ isTyping } = {}) => {
      const currentRoom = [...socket.rooms].find(r => r !== socket.id);
      if (!currentRoom) return;
      const username = store.getUsername(socket.id);
      if (!username) return;
      socket.to(currentRoom).emit('typing', { username, isTyping: !!isTyping });
    });

    socket.on('disconnect', () => {
      const removed = store.removeUser(socket.id);
      if (removed) {
        io.to(removed.currentRoom).emit('userLeft', { username: removed.username });
      }
    });
  });
}
