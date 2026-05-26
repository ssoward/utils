# ChromeCC

Chat with Claude about any web page, powered by your local Claude Code login.

## How It Works

ChromeCC is a Chrome extension that opens a chat sidebar. It connects to your locally installed `claude` CLI through Chrome's Native Messaging API, so it uses your existing Claude Code authentication — no separate API keys needed.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and logged in
- Node.js (v18+)
- Google Chrome

## Setup

1. **Load the extension:**
   - Open `chrome://extensions`
   - Enable "Developer mode"
   - Click "Load unpacked" and select this directory
   - Copy the extension ID shown

2. **Install the native messaging host:**
   ```bash
   ./native-host/install.sh YOUR_EXTENSION_ID
   ```

3. **Restart Chrome** and click the ChromeCC icon on any page.

## Usage

- Click the ChromeCC icon to open the sidebar
- Type a message and press Enter
- Claude automatically sees the page you're on
- Select text on the page to include it as focused context
- Click the trash icon to start a new conversation

## Architecture

```
Chrome Side Panel  <-->  Background Worker  <-->  Native Host (Node.js)  <-->  claude -p
```

The extension extracts page content and sends it alongside your messages through Chrome's Native Messaging protocol to a small Node.js script that spawns `claude -p` (print mode). Your existing Claude Code login handles authentication.
