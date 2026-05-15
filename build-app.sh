#!/usr/bin/env bash
# Build BrotherPaul.app — a real macOS .app bundle wrapping the Swift Package
# executable, so it appears in /Applications, Launchpad, and Shortcuts.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="BrotherPaul"
BUILD_DIR="${ROOT}/build"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_PATH}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

echo "→ Building release binary…"
cd "${ROOT}"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
    echo "Build did not produce ${BIN_PATH}" >&2
    exit 1
fi

echo "→ Assembling ${APP_NAME}.app…"
rm -rf "${APP_PATH}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
cp "${ROOT}/Resources/Info.plist" "${CONTENTS}/Info.plist"
cp "${ROOT}/Resources/config.example.json" "${RESOURCES_DIR}/config.example.json"

# Ad-hoc sign so Gatekeeper doesn't refuse to launch the binary.
codesign --force --deep --sign - "${APP_PATH}" >/dev/null 2>&1 || true

echo "✓ Built ${APP_PATH}"
echo
echo "Next:"
echo "  open ${APP_PATH}"
echo "  # or copy it into /Applications:"
echo "  cp -R ${APP_PATH} /Applications/"
