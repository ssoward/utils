#!/bin/bash
set -e

# ChromeCC Native Messaging Host installer (macOS)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST_PATH="$SCRIPT_DIR/host.js"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST_TEMPLATE="$PROJECT_DIR/com.anthropic.chromecc.json"
NM_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
MANIFEST_DEST="$NM_DIR/com.anthropic.chromecc.json"

echo "ChromeCC Native Host Installer"
echo "==============================="
echo ""

# Check that claude CLI exists
if ! command -v claude &> /dev/null; then
  echo "ERROR: 'claude' CLI not found on PATH."
  echo "Install Claude Code first: https://docs.anthropic.com/en/docs/claude-code"
  exit 1
fi

echo "[OK] claude CLI found: $(which claude)"

# Check that node exists
if ! command -v node &> /dev/null; then
  echo "ERROR: 'node' not found on PATH."
  echo "Install Node.js first: https://nodejs.org"
  exit 1
fi

echo "[OK] node found: $(which node)"

# Make host.js executable
chmod +x "$HOST_PATH"
echo "[OK] Made host.js executable"

# Get extension ID
if [ -z "$1" ]; then
  echo ""
  echo "IMPORTANT: You need your Chrome extension ID."
  echo "1. Go to chrome://extensions"
  echo "2. Enable Developer mode"
  echo "3. Load unpacked -> select the chromeCC directory"
  echo "4. Copy the extension ID (e.g., abcdefghijklmnopqrstuvwxyz)"
  echo ""
  read -p "Enter your extension ID: " EXT_ID
else
  EXT_ID="$1"
fi

if [ -z "$EXT_ID" ]; then
  echo "ERROR: Extension ID is required."
  exit 1
fi

# Create NativeMessagingHosts directory if needed
mkdir -p "$NM_DIR"

# Write the manifest with correct paths
cat > "$MANIFEST_DEST" << EOF
{
  "name": "com.anthropic.chromecc",
  "description": "ChromeCC - Claude Code Chat for Chrome",
  "path": "$HOST_PATH",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$EXT_ID/"
  ]
}
EOF

echo "[OK] Installed native host manifest to: $MANIFEST_DEST"
echo ""
echo "Setup complete! Restart Chrome and open the ChromeCC sidebar."
