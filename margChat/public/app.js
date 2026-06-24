const socket = io();

const modal = document.getElementById('username-modal');
const usernameInput = document.getElementById('username-input');
const usernameError = document.getElementById('username-error');
const usernameGo = document.getElementById('username-go');
const app = document.getElementById('app');
const meUsername = document.getElementById('me-username');

let myUsername = null;
let pendingUsername = null;
let currentRoom = 'lobby';

function showError(msg) {
  usernameError.textContent = msg || '';
}

function attemptJoin() {
  const name = usernameInput.value.trim();
  if (!name) return showError('Please enter a username.');
  showError('');
  socket.emit('join', { username: name });
  pendingUsername = name;
}

usernameGo.addEventListener('click', attemptJoin);
usernameInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') attemptJoin();
});

socket.on('errorMsg', (err) => {
  if (pendingUsername) {
    pendingUsername = null;
    return showError(err.message);
  }
  // For non-join errors, surface in console for now (next tasks will use a toast).
  console.warn('server error', err);
});

const messagesEl = document.getElementById('messages');
const sendForm = document.getElementById('send-form');
const sendInput = document.getElementById('send-input');
const topbarRoom = document.getElementById('topbar-room');

function formatTs(ts) {
  const d = new Date(ts);
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function nearBottom() {
  const slack = 60;
  return messagesEl.scrollHeight - messagesEl.scrollTop - messagesEl.clientHeight < slack;
}

function appendMessage(msg) {
  const wasNearBottom = nearBottom();
  const el = document.createElement('div');
  el.className = 'message';
  el.innerHTML = `<span class="from"></span><span class="body"></span><span class="ts"></span>`;
  el.querySelector('.from').textContent = msg.from;
  el.querySelector('.body').textContent = msg.text;
  el.querySelector('.ts').textContent = formatTs(msg.ts);
  messagesEl.appendChild(el);
  if (wasNearBottom) messagesEl.scrollTop = messagesEl.scrollHeight;
}

function renderRoom(state) {
  messagesEl.innerHTML = '';
  for (const m of state.recentMessages) appendMessage(m);
  topbarRoom.textContent = state.room;
}

socket.on('message', (msg) => appendMessage(msg));

const roomsList = document.getElementById('rooms-list');
const newRoomForm = document.getElementById('new-room-form');
const newRoomInput = document.getElementById('new-room-input');
const currentRoomLabel = document.getElementById('current-room-label');

function renderRoomsList(state) {
  roomsList.innerHTML = '';
  for (const room of state.rooms) {
    const li = document.createElement('li');
    li.textContent = room;
    if (room === state.room) li.classList.add('active');
    li.addEventListener('click', () => {
      if (room !== currentRoom) socket.emit('switchRoom', { room });
    });
    roomsList.appendChild(li);
  }
  currentRoomLabel.textContent = state.room;
}

newRoomForm.addEventListener('submit', (e) => {
  e.preventDefault();
  const name = newRoomInput.value.trim();
  if (!name) return;
  socket.emit('switchRoom', { room: name });
  newRoomInput.value = '';
});

const usersList = document.getElementById('users-list');
const typingStrip = document.getElementById('typing-strip');

let currentUsers = [];
const typingPeers = new Map(); // username -> timeoutId

function renderUsers() {
  usersList.innerHTML = '';
  for (const u of currentUsers) {
    const li = document.createElement('li');
    li.textContent = u;
    usersList.appendChild(li);
  }
}

function renderTyping() {
  const names = [...typingPeers.keys()];
  if (names.length === 0) { typingStrip.textContent = ''; return; }
  if (names.length === 1) typingStrip.textContent = `${names[0]} is typing…`;
  else if (names.length === 2) typingStrip.textContent = `${names[0]} and ${names[1]} are typing…`;
  else typingStrip.textContent = `several people are typing…`;
}

socket.on('roomState', (state) => {
  if (modal && !modal.hidden) {
    myUsername = pendingUsername;
    pendingUsername = null;
    modal.hidden = true;
    app.hidden = false;
    meUsername.textContent = myUsername;
  }
  currentRoom = state.room;
  currentUsers = state.users.slice();
  typingPeers.clear();
  renderRoom(state);
  renderRoomsList(state);
  renderUsers();
  renderTyping();
  window._roomState = state;
});

socket.on('userJoined', ({ username }) => {
  if (!currentUsers.includes(username)) currentUsers.push(username);
  renderUsers();
});

socket.on('userLeft', ({ username }) => {
  currentUsers = currentUsers.filter(u => u !== username);
  typingPeers.delete(username);
  renderUsers();
  renderTyping();
});

socket.on('typing', ({ username, isTyping }) => {
  if (isTyping) {
    if (typingPeers.has(username)) clearTimeout(typingPeers.get(username));
    typingPeers.set(username, setTimeout(() => {
      typingPeers.delete(username);
      renderTyping();
    }, 3000));
  } else {
    if (typingPeers.has(username)) clearTimeout(typingPeers.get(username));
    typingPeers.delete(username);
  }
  renderTyping();
});

let typingTimer = null;
let typingActive = false;

sendForm.addEventListener('submit', (e) => {
  e.preventDefault();
  if (typingActive) {
    typingActive = false;
    if (typingTimer) clearTimeout(typingTimer);
    socket.emit('typing', { isTyping: false });
  }
  const text = sendInput.value.trim();
  if (!text) return;
  socket.emit('sendMessage', { text });
  sendInput.value = '';
});

sendInput.addEventListener('input', () => {
  if (!typingActive) {
    typingActive = true;
    socket.emit('typing', { isTyping: true });
  }
  if (typingTimer) clearTimeout(typingTimer);
  typingTimer = setTimeout(() => {
    typingActive = false;
    socket.emit('typing', { isTyping: false });
  }, 1500);
});
