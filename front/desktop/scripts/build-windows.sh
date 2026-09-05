#!/usr/bin/env bash
# Cross-building a full Windows installer from Linux needs a Windows WebView2/NSIS
# toolchain. This script prepares the Windows Go sidecar and documents the
# supported path: run `npm run tauri build` on a Windows machine.
set -euo pipefail

DESKTOP="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DESKTOP"

bash ./scripts/prepare-sidecar.sh windows

cat <<'EOF'

Windows sidecar prepared under src-tauri/binaries/.

To produce the .msi/.exe installer, on a Windows host with:
  - Node.js + Rust (MSVC)
  - WebView2 runtime
run:

  cd desktop
  npm install
  npm run prepare:sidecar   # or copy vaporcito-x86_64-pc-windows-msvc.exe
  npm run tauri build

Artifacts appear under src-tauri/target/release/bundle/.
EOF
