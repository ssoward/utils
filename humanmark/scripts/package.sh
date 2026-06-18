#!/usr/bin/env bash
# Builds the extension and creates a Chrome Web Store-ready ZIP.
# Usage: ./scripts/package.sh [version]
set -euo pipefail

VERSION=${1:-$(node -p "require('./package.json').version")}
OUT="humanmark-v${VERSION}.zip"

echo "→ Building..."
npm run build

echo "→ Zipping dist/ → ${OUT}"
cd dist
zip -r "../${OUT}" . \
  --exclude "*.map" \
  --exclude "*.DS_Store" \
  --exclude "__MACOSX/*"
cd ..

echo "✓ ${OUT} ready ($(du -sh "${OUT}" | cut -f1))"
echo ""
echo "Next steps:"
echo "  1. Go to https://chrome.google.com/webstore/devconsole"
echo "  2. Click 'Add new item' and upload ${OUT}"
echo "  3. Fill in store listing, privacy policy URL, permission justifications"
echo "  4. Submit for review"
