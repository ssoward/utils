#!/usr/bin/env bash
# Install (or refresh) the Brother Paul LaunchAgent so the menu-bar app starts
# automatically at login. Idempotent: safe to run repeatedly / after a redeploy.
#
# Usage:
#   bin/install-login-item.sh            # install + load
#   bin/install-login-item.sh --uninstall  # unload + remove

set -euo pipefail

LABEL="com.sls.brotherpaul"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="${ROOT}/Resources/${LABEL}.plist"
AGENTS_DIR="${HOME}/Library/LaunchAgents"
DEST="${AGENTS_DIR}/${LABEL}.plist"
DOMAIN="gui/$(id -u)"

uninstall() {
    echo "→ Removing Brother Paul LaunchAgent…"
    launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
    rm -f "${DEST}"
    echo "✓ Uninstalled. Brother Paul will no longer start at login."
    exit 0
}

[[ "${1:-}" == "--uninstall" ]] && uninstall

# Resolve the installed app: prefer /Applications, fall back to ~/Applications.
APP=""
for candidate in "/Applications/BrotherPaul.app" "${HOME}/Applications/BrotherPaul.app"; do
    if [[ -x "${candidate}/Contents/MacOS/BrotherPaul" ]]; then
        APP="${candidate}"
        break
    fi
done
if [[ -z "${APP}" ]]; then
    echo "✗ BrotherPaul.app not found in /Applications or ~/Applications." >&2
    echo "  Build & deploy it first (./build-app.sh), then re-run this script." >&2
    exit 1
fi
BIN="${APP}/Contents/MacOS/BrotherPaul"
echo "→ Using app at ${APP}"

# Write the plist with the resolved binary path substituted in.
mkdir -p "${AGENTS_DIR}"
sed "s#/Applications/BrotherPaul.app/Contents/MacOS/BrotherPaul#${BIN}#" \
    "${TEMPLATE}" > "${DEST}"
echo "→ Installed ${DEST}"

# (Re)load. bootout first so an existing definition is replaced cleanly.
launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
launchctl bootstrap "${DOMAIN}" "${DEST}"
launchctl enable "${DOMAIN}/${LABEL}"

echo "✓ Brother Paul is now set to launch at login."
echo "  Verify:  launchctl print ${DOMAIN}/${LABEL} | grep -E 'state|program'"
