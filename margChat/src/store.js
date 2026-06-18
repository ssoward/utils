export function createStore() {
  const users = new Map(); // socketId -> { socketId, username, currentRoom }
  const rooms = new Map(); // name -> { name, users: Set<socketId>, messages: [] }

  function ensureRoom(name) {
    if (!rooms.has(name)) {
      rooms.set(name, { name, users: new Set(), messages: [] });
    }
    return rooms.get(name);
  }

  ensureRoom('lobby');

  function isUsernameTaken(username) {
    for (const u of users.values()) {
      if (u.username === username) return true;
    }
    return false;
  }

  function joinRoom(socketId, username, roomName = 'lobby') {
    if (isUsernameTaken(username)) {
      throw new Error('USERNAME_TAKEN');
    }
    const room = ensureRoom(roomName);
    const user = { socketId, username, currentRoom: roomName };
    users.set(socketId, user);
    room.users.add(socketId);
    return user;
  }

  function getRoomState(roomName) {
    const room = rooms.get(roomName);
    if (!room) return null;
    const memberUsernames = [...room.users]
      .map(id => users.get(id)?.username)
      .filter(Boolean);
    return {
      room: room.name,
      users: memberUsernames,
      recentMessages: [...room.messages],
      rooms: [...rooms.keys()],
    };
  }

  function addMessage(socketId, text) {
    const user = users.get(socketId);
    if (!user) throw new Error('NO_USER');
    const room = rooms.get(user.currentRoom);
    const msg = { from: user.username, text, ts: Date.now() };
    room.messages.push(msg);
    if (room.messages.length > 50) room.messages.shift();
    return msg;
  }

  function switchRoom(socketId, targetName) {
    const user = users.get(socketId);
    if (!user) throw new Error('NO_USER');
    const prev = rooms.get(user.currentRoom);
    if (prev) {
      prev.users.delete(socketId);
      if (prev.name !== 'lobby' && prev.users.size === 0) {
        rooms.delete(prev.name);
      }
    }
    const target = ensureRoom(targetName);
    target.users.add(socketId);
    user.currentRoom = targetName;
    return target;
  }

  function getUsername(socketId) {
    return users.get(socketId)?.username;
  }

  function removeUser(socketId) {
    const user = users.get(socketId);
    if (!user) return undefined;
    const room = rooms.get(user.currentRoom);
    if (room) {
      room.users.delete(socketId);
      if (room.name !== 'lobby' && room.users.size === 0) {
        rooms.delete(room.name);
      }
    }
    users.delete(socketId);
    return user;
  }

  return { joinRoom, switchRoom, addMessage, removeUser, getRoomState, getUsername };
}
