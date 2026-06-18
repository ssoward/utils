# margChat — PRD / Design

**Date:** 2026-05-15
**Owner:** @ssoward
**Status:** Draft for review

## 1. Summary

margChat is a lightweight, socket-based group chat that runs as a single Node.js process. The owner runs it locally and exposes it to the public internet via a tunnel (ngrok / Cloudflare Tunnel). Anyone with the link can pick a display name and chat in real time, in a default "lobby" room or in user-created rooms. All state is in-memory; restart wipes everything.

## 2. Goals / Non-goals

**Goals**
- Share a link with friends/coworkers and chat in real time.
- Modern, clean UI (Slack/Discord-lite): sidebar with rooms + online users, message pane, input.
- Multiple rooms; typing indicators; online user list.
- Zero infrastructure to operate (no DB, no auth service, no build step).

**Non-goals (v1)**
- Accounts, passwords, identity. Username on join only.
- Message persistence across restarts.
- File uploads, images, reactions, threads, DMs.
- Mobile-native apps. Browser only.
- Horizontal scaling / multi-process.

## 3. User stories

- As the owner, I can run `node server.js`, expose it with `ngrok http 3000`, and share the URL.
- As a visitor, I can open the link, type a display name, and immediately be in the lobby.
- As a chatter, I can send messages, see other people's messages instantly, and see who is online.
- As a chatter, I can create or join another named room by typing its name; I see the room's recent history (up to 50 messages).
- As a chatter, I can see when someone else is typing.

## 4. Architecture

Single Node.js process. Express serves the static client; Socket.IO is mounted on the same HTTP server. State is held in memory.

```
[browser]  <-- HTTPS via tunnel -->  [Node server]
   |                                     |
   | Socket.IO (WebSocket)               +-- in-memory state:
   |                                          - rooms (Map: name -> Room)
   v                                          - users  (Map: socketId -> User)
[index.html + app.js + style.css]             - lobby always exists
```

**Why:** zero infra; one command to run; trivially tunneled; ephemeral state matches the social-trust model (open link, friends only).

## 5. File layout

```
margChat/
├── package.json
├── server.js              # HTTP + Socket.IO bootstrap, wires handlers
├── src/
│   ├── store.js           # in-memory rooms/users state, pure-ish API
│   └── handlers.js        # socket event handlers (uses store)
├── public/
│   ├── index.html         # markup: sidebar + main pane + input
│   ├── app.js             # client socket logic + DOM updates
│   └── style.css          # Slack-lite theme
└── test/
    └── store.test.js      # unit tests for the store
```

**Boundaries**
- `store.js` knows nothing about sockets. Pure data + functions: `joinRoom`, `addMessage`, `removeUser`, `switchRoom`, `getRoomState`. Testable without a network.
- `handlers.js` is glue: parses socket events, calls store, emits responses/broadcasts.
- `server.js` only wires Express, Socket.IO, and the handlers together. No business logic.

## 6. Data model (in-memory)

```js
User = { socketId, username, currentRoom }
Room = {
  name,
  users: Set<socketId>,
  messages: RingBuffer<Message>(50)   // last 50, oldest evicted first
}
Message = { from: username, text, ts: epochMs }
```

- `lobby` is created at startup and never garbage-collected.
- Other rooms are created on demand (first `switchRoom` to that name) and removed when the last user leaves.

## 7. Socket protocol

**Client → Server**
| Event | Payload | Effect |
|---|---|---|
| `join` | `{ username }` | Register user, place in `lobby`, emit `roomState` to caller, `userJoined` to room |
| `switchRoom` | `{ room }` | Leave current room (broadcast `userLeft`), join target (create if new), emit `roomState` |
| `sendMessage` | `{ text }` | Validate, broadcast `message` to current room, append to ring buffer |
| `typing` | `{ isTyping }` | Broadcast `typing` to others in room (no storage) |

**Server → Client**
| Event | Payload | When |
|---|---|---|
| `roomState` | `{ room, users[], recentMessages[], rooms[] }` | On join / switchRoom |
| `message` | `{ from, text, ts }` | New message in current room |
| `userJoined` | `{ username }` | Member added to current room |
| `userLeft` | `{ username }` | Member removed from current room |
| `typing` | `{ username, isTyping }` | Someone else typing |
| `errorMsg` | `{ code, message }` | Validation / rate-limit failures |

## 8. UI (Slack-lite)

- **Left sidebar (≈220px):** "Rooms" list (clickable, current room highlighted) with a "+ New room" input at the bottom. Below that, "Online in this room" list.
- **Main pane:** scrollable message list. Each message: bold username, lighter timestamp, body. Auto-scroll to bottom on new message *only if* user is already near the bottom.
- **Bottom bar:** single-line text input + Send button. Enter to send, Shift+Enter inserts newline. Typing indicator strip ("alice is typing…") above the input.
- **Username prompt:** modal/overlay on first load; blocks the UI until a valid username is accepted.
- Light theme, system font stack, vanilla CSS (no framework, no build step).

## 9. Validation & limits

| Field | Rule | On failure |
|---|---|---|
| Username | 1–24 chars, trimmed, `[a-zA-Z0-9_\- ]` | `errorMsg { code: "USERNAME_INVALID" }` |
| Username uniqueness | Unique per server (not just per room) | `errorMsg { code: "USERNAME_TAKEN" }`, client re-prompts |
| Message text | 1–2000 chars after trim | `errorMsg { code: "MESSAGE_INVALID" }` |
| Room name | 1–32 chars, same charset as username | `errorMsg { code: "ROOM_INVALID" }` |
| Rate limit | 5 messages / 2s per socket (token bucket) | `errorMsg { code: "RATE_LIMITED" }`, message dropped |

All validation is server-side. Client may pre-check for UX but never trusted.

## 10. Failure modes

- **Client disconnect:** server removes user from any room, broadcasts `userLeft`, GCs empty non-lobby rooms.
- **Client reconnect:** treated as a fresh session. Old socket's user is already gone; user re-enters username.
- **Server crash / restart:** all rooms and messages lost. Acceptable per ephemeral choice. Clients see disconnect, can reconnect when server returns.
- **Bad payload (missing/typed fields):** `errorMsg` emitted, server keeps running.
- **Tunnel drops:** out of scope; user restarts the tunnel.

## 11. Testing

- **Unit (`test/store.test.js`, `node:test`):**
  - join/leave updates user list correctly
  - duplicate username rejected
  - ring buffer evicts at 51st message
  - empty non-lobby room is removed; lobby is never removed
  - room auto-created on switchRoom to a new name
- **Integration (one happy path):**
  - Boot server on a random port, two Socket.IO test clients connect and `join` lobby.
  - Client A `sendMessage` → assert Client B receives `message`.
  - Client A `switchRoom` to "alpha" → assert Client B no longer receives A's messages.
- **No E2E / browser tests in v1.** Manual smoke via the real UI is sufficient.

## 12. Deployment / sharing

- `npm install`
- `node server.js` (listens on `PORT` env var, default 3000)
- `ngrok http 3000` (or `cloudflared tunnel --url http://localhost:3000`) → share the printed HTTPS URL
- README documents both options.

## 13. Open questions

None blocking v1.

## 14. Out-of-scope follow-ups (captured, not committed)

- Optional shared-passphrase gate (server env var) if drive-by joiners become a problem.
- SQLite persistence for message history.
- DMs / private rooms.
- Markdown rendering / link previews.
- Cloud deployment (Fly.io / Render) for a stable URL.
