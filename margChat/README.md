# margChat

Lightweight socket-based group chat. Single Node.js process, in-memory state, share via a tunnel.

## Run locally

```bash
npm install
npm start
```

Then open http://localhost:3000.

## Share with others (public via tunnel)

Pick one of the following:

### ngrok

```bash
ngrok http 3000
```

Share the printed `https://*.ngrok-free.app` URL.

### Cloudflare Tunnel

```bash
cloudflared tunnel --url http://localhost:3000
```

Share the printed `https://*.trycloudflare.com` URL.

## Features

- Pick a display name and chat — no accounts.
- Default `lobby` room plus any rooms you create by typing a new room name.
- Typing indicators and live user list per room.
- Last 50 messages per room are shown to new joiners. All state is lost when the server restarts.

## Tests

```bash
npm test
```

## Limits

- Username: 1-24 chars, server-wide unique.
- Message: 1-2000 chars, 5 messages per 2-second rate limit per socket.
- Room name: 1-32 chars.

## Configuration

- `PORT` — HTTP port (default `3000`).
- `ALLOWED_ORIGINS` — comma-separated list of allowed Socket.IO origins. Default `*` (any). For a locked-down local run, set e.g. `ALLOWED_ORIGINS=http://localhost:3000`. For a tunnel deployment, set it to your tunnel URL.

## Security notes

- There is no authentication. Anyone with the URL can join.
- Always share via HTTPS (ngrok / Cloudflare Tunnel). Do not share `http://<lan-ip>:3000` directly — that traffic is unencrypted.
- All state is in-memory; restart wipes everything.
