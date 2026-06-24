#!/usr/bin/env bash
# Run the full Brother Paul test suite: XCTest units, then the bin/smoke-test.sh
# end-to-end harness. Exits non-zero on any failure.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

echo "=== Unit tests (swift test) ==="
swift test

echo
echo "=== Smoke tests (bin/smoke-test.sh) ==="
./bin/smoke-test.sh

echo
echo "All tests passed."
