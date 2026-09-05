#!/usr/bin/env bash
set -euo pipefail

DESKTOP="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DESKTOP"

bash ./scripts/prepare-sidecar.sh linux
npm install
npm run tauri build

echo
echo "Linux bundles (if toolchain deps are installed):"
find src-tauri/target/release/bundle -type f 2>/dev/null | sed 's/^/  /' || true
