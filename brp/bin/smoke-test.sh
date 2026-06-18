#!/usr/bin/env bash
# Smoke test for BrotherPaul: exercises the real .app through brotherpaul://
# URLs against a hermetic fixture config. Safe to run on a normal Mac because
# we refuse to start if the target test apps (TextEdit, Calculator) are
# already running.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="/Applications/BrotherPaul.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Support/lsregister"

TMP_DIR=""
PASS=0
FAIL=0

# ---- helpers ----------------------------------------------------------------

cleanup() {
    set +e
    pkill -x BrotherPaul 2>/dev/null
    pkill -x TextEdit 2>/dev/null
    pkill -x Calculator 2>/dev/null
    launchctl unsetenv BROTHERPAUL_CONFIG_DIR 2>/dev/null
    if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
        rm -rf "${TMP_DIR}"
    fi
}
trap cleanup EXIT INT TERM

ok()   { echo "✓ $*"; PASS=$((PASS+1)); }
fail() { echo "✗ $*" >&2; FAIL=$((FAIL+1)); }

# Wait until $1 (a pgrep -x name) is running, up to $2 seconds. Returns 0 on success.
wait_for_proc() {
    local name="$1"; local timeout="${2:-10}"
    for _ in $(seq 1 "$timeout"); do
        if pgrep -x "$name" >/dev/null; then return 0; fi
        sleep 1
    done
    return 1
}

# Wait until $1 is NOT running, up to $2 seconds.
wait_for_no_proc() {
    local name="$1"; local timeout="${2:-10}"
    for _ in $(seq 1 "$timeout"); do
        if ! pgrep -x "$name" >/dev/null; then return 0; fi
        sleep 1
    done
    return 1
}

# ---- 1. Pre-flight ----------------------------------------------------------

if [[ ! -d "${APP_PATH}" ]]; then
    fail "BrotherPaul.app missing at ${APP_PATH}. Run ./build-app.sh first."
    exit 2
fi

if pgrep -x TextEdit >/dev/null; then
    fail "TextEdit is already running — refusing to nuke your live work. Quit it and retry."
    exit 2
fi
if pgrep -x Calculator >/dev/null; then
    fail "Calculator is already running — refusing to nuke your live work. Quit it and retry."
    exit 2
fi
ok "Pre-flight clean"

# ---- 2. Build & install -----------------------------------------------------

(cd "${ROOT}" && ./build-app.sh >/dev/null)
ok "Built and installed"

# ---- 3. Stage fixture config ------------------------------------------------

TMP_DIR="$(mktemp -d -t brpaul-smoke)"
cat > "${TMP_DIR}/config.json" <<'JSON'
{
  "hideOthersAfterLaunch": false,
  "defaultMode": "SmokeStart",
  "modes": [
    { "name": "SmokeStart", "apps": ["TextEdit", "Calculator"], "urls": [] }
  ],
  "enableSnap": false,
  "enableDragSnap": false,
  "missionControl": {
    "includeCalendar": false,
    "includeOutlook": false,
    "includeOutlookCalendar": false,
    "includeGraphCalendar": false,
    "includeGmail": false,
    "includeNotifications": false,
    "includeVerseOfDay": false,
    "lookbackHours": 24,
    "vipSenders": [],
    "notificationAppBlocklist": [],
    "openOnStartWork": false,
    "quickLinks": [],
    "gmail": { "clientID": "", "clientSecret": "", "refreshToken": "" },
    "graph": { "clientID": "", "tenant": "common", "refreshToken": "" }
  }
}
JSON

# ---- 4. Cold-launch BrotherPaul with the override ---------------------------

pkill -x BrotherPaul 2>/dev/null || true
sleep 1
launchctl setenv BROTHERPAUL_CONFIG_DIR "${TMP_DIR}"
"${LSREGISTER}" -f "${APP_PATH}" >/dev/null 2>&1 || true
open -gj "${APP_PATH}"

if wait_for_proc BrotherPaul 10; then
    ok "Cold launch with BROTHERPAUL_CONFIG_DIR=${TMP_DIR}"
else
    fail "BrotherPaul did not start within 10s"
    exit 1
fi
sleep 1  # let applicationDidFinishLaunching settle

# ---- 5. Positive start ------------------------------------------------------

open "brotherpaul://start?mode=SmokeStart"

if wait_for_proc TextEdit 10 && wait_for_proc Calculator 10; then
    ok "Start SmokeStart → TextEdit + Calculator up"
else
    fail "TextEdit and/or Calculator did not launch within 10s"
fi

# ---- 6. Positive stop -------------------------------------------------------

open "brotherpaul://stop?mode=SmokeStart"

if wait_for_no_proc TextEdit 10 && wait_for_no_proc Calculator 10; then
    ok "Stop SmokeStart → both quit"
else
    fail "TextEdit and/or Calculator did not quit within 10s"
fi

# ---- 7. Negative: unknown mode ---------------------------------------------

# Sentinel: nothing should launch.
before="$(pgrep -lx TextEdit; pgrep -lx Calculator || true)"
open "brotherpaul://start?mode=DoesNotExist"
sleep 2
after="$(pgrep -lx TextEdit; pgrep -lx Calculator || true)"

if [[ "${before}" == "${after}" ]]; then
    ok "Start DoesNotExist → no apps launched"
else
    fail "Unknown mode caused unexpected launches: diff '${before}' → '${after}'"
fi

# Confirm the log shows the unknown-mode branch actually ran.
if log show --predicate 'process == "BrotherPaul"' --last 30s 2>/dev/null \
   | grep -q "unknown mode 'DoesNotExist'"; then
    ok "Log records: unknown mode 'DoesNotExist'"
else
    # NSLog can take a moment to surface; soft-fail to a warning rather than hard fail.
    echo "⚠ Could not confirm 'unknown mode' log entry (NSLog may be delayed; check manually if this happens repeatedly)"
fi

# ---- Summary ----------------------------------------------------------------

echo
echo "PASS=${PASS}  FAIL=${FAIL}"
if [[ "${FAIL}" -gt 0 ]]; then
    exit 1
fi
echo "All smoke checks passed."
