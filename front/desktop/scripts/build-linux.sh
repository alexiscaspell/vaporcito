#!/usr/bin/env bash
# Build the Linux desktop app (Tauri) with embedded Go sidecar.
set -euo pipefail

# Prefer nvm Node (>=20) and cargo over system/Cursor helpers.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  # shellcheck source=/dev/null
  source "$NVM_DIR/nvm.sh"
  nvm use default >/dev/null 2>&1 || nvm use 22 >/dev/null 2>&1 || true
fi
export PATH="${HOME}/.cargo/bin:${PATH:-/usr/bin}"
if [[ -f "${HOME}/.cargo/env" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.cargo/env"
fi

NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)"
if [[ "$NODE_MAJOR" -lt 20 ]]; then
  echo "Node.js >= 20 required (found $(node -v 2>/dev/null || echo none))." >&2
  echo "Install with nvm: curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash && nvm install 22" >&2
  exit 1
fi

if ! command -v rustc >/dev/null 2>&1; then
  echo "rustc not found. Install Rust from https://rustup.rs and reopen the terminal." >&2
  echo "Or: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" >&2
  exit 1
fi

DESKTOP="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DESKTOP"

VERSION="${VERSION:-}"
BUNDLE_VERSION="${BUNDLE_VERSION:-}"

if [[ -n "$VERSION" ]]; then
  export VERSION
  export FORCE_REBUILD="${FORCE_REBUILD:-1}"
fi

# Tauri/WiX need a numeric X.Y.Z for the bundle metadata.
if [[ -n "$BUNDLE_VERSION" ]]; then
  python3 - <<'PY' "$BUNDLE_VERSION" "$DESKTOP"
import json, sys
from pathlib import Path
ver, root = sys.argv[1], Path(sys.argv[2])
# Strip prerelease / build metadata if someone passed a full SemVer.
core = ver.split("+", 1)[0].split("-", 1)[0].lstrip("v")
parts = core.split(".")
if len(parts) != 3 or not all(p.isdigit() for p in parts):
    raise SystemExit(f"BUNDLE_VERSION must be MAJOR.MINOR.PATCH, got {ver!r}")
for rel in ("package.json", "src-tauri/tauri.conf.json"):
    path = root / rel
    data = json.loads(path.read_text())
    data["version"] = core
    path.write_text(json.dumps(data, indent=2) + "\n")
    print(f"Set {rel} version={core}")
PY
fi

bash ./scripts/prepare-sidecar.sh linux
npm install

# AppImage needs librsvg2-dev (pkg-config librsvg-2.0) + FUSE workaround on many distros.
export APPIMAGE_EXTRACT_AND_RUN=1
BUNDLE_ARGS=(--bundles deb,rpm)
if pkg-config --exists librsvg-2.0 2>/dev/null; then
  BUNDLE_ARGS=(--bundles deb,rpm,appimage)
else
  echo "Note: librsvg2-dev not found — skipping AppImage."
  echo "  Install with: sudo apt install librsvg2-dev"
  echo "  Continuing with deb + rpm only."
fi

npm run tauri build -- "${BUNDLE_ARGS[@]}"

echo
echo "Linux bundles:"
find src-tauri/target/release/bundle -type f \( -name '*.deb' -o -name '*.rpm' -o -name '*.AppImage' \) 2>/dev/null | sed 's/^/  /' || true
