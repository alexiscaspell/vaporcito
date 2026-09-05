#!/usr/bin/env bash
# Copy / build the Go engine into src-tauri/binaries with the Tauri sidecar name.
#
# Env:
#   VERSION  – string passed to build.go -version (default: v1.0.0-vaporcito)
#   FORCE_REBUILD=1 – rebuild even if binary exists
set -euo pipefail

# npm scripts often omit ~/.cargo/bin (no login shell).
export PATH="${HOME}/.cargo/bin:${PATH:-/usr/bin}"

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
BACK="$ROOT/back"
DESKTOP="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$DESKTOP/src-tauri/binaries"
mkdir -p "$BIN_DIR"

TARGET="${1:-native}"
VERSION="${VERSION:-v1.0.0-vaporcito}"
# Go -version expects a leading v for consistency with git tags.
case "$VERSION" in
  v*) ;;
  *) VERSION="v${VERSION}" ;;
esac

host_triple() {
  if ! command -v rustc >/dev/null 2>&1; then
    return 0
  fi
  rustc -Vv 2>/dev/null | awk '/^host:/{print $2; exit}' || true
}

copy_named() {
  local src="$1"
  local triple="$2"
  local dest="$BIN_DIR/vaporcito-${triple}"
  if [[ "$triple" == *windows* ]]; then
    dest="${dest}.exe"
  fi
  cp -f "$src" "$dest"
  chmod +x "$dest" 2>/dev/null || true
  echo "Sidecar ready: $dest"
}

build_go() {
  local goos="$1"
  local goarch="$2"
  local out_name="$3"

  (
    cd "$BACK"
    if command -v go >/dev/null 2>&1; then
      echo "Building Go sidecar (${goos}/${goarch}) with local Go, version ${VERSION}..."
      CGO_ENABLED=0 GOFLAGS="${GOFLAGS:--buildvcs=false}" \
        go run build.go \
          -goos "$goos" -goarch "$goarch" \
          -no-upgrade \
          -version "$VERSION" \
          build
    else
      echo "Building Go sidecar (${goos}/${goarch}) via Docker, version ${VERSION}..."
      docker run --rm \
        -v "$ROOT":/src \
        -w /src/back \
        -e CGO_ENABLED=0 \
        -e GOFLAGS=-buildvcs=false \
        -u "$(id -u):$(id -g)" \
        -e HOME=/tmp \
        golang:1.22-bookworm \
        bash -c "git config --global --add safe.directory /src && go run build.go -goos ${goos} -goarch ${goarch} -no-upgrade -version ${VERSION} build"
    fi
  )

  if [[ ! -f "$BACK/$out_name" ]]; then
    echo "Expected output missing: $BACK/$out_name" >&2
    exit 1
  fi
}

build_go_linux() {
  local out="$BACK/vaporcito"
  if [[ "${FORCE_REBUILD:-0}" == "1" || ! -x "$out" ]]; then
    build_go linux amd64 vaporcito
  else
    echo "Reusing existing $out"
  fi
  copy_named "$out" "x86_64-unknown-linux-gnu"
}

build_go_windows() {
  local out="$BACK/vaporcito.exe"
  if [[ "${FORCE_REBUILD:-0}" == "1" || ! -f "$out" ]]; then
    build_go windows amd64 vaporcito.exe
  else
    echo "Reusing existing $out"
  fi
  copy_named "$out" "x86_64-pc-windows-msvc"
}

case "$TARGET" in
  native|linux)
    if [[ "$(uname -s)" == "Linux" ]]; then
      build_go_linux
      host="$(host_triple)"
      if [[ -n "$host" && "$host" != "x86_64-unknown-linux-gnu" && -f "$BIN_DIR/vaporcito-x86_64-unknown-linux-gnu" ]]; then
        cp -f "$BIN_DIR/vaporcito-x86_64-unknown-linux-gnu" "$BIN_DIR/vaporcito-$host"
      fi
    else
      echo "On this OS use: $0 windows   or build the Go binary and copy it manually."
      exit 1
    fi
    ;;
  windows)
    build_go_windows
    ;;
  all)
    build_go_linux
    build_go_windows
    ;;
  *)
    echo "Usage: $0 [native|linux|windows|all]"
    exit 1
    ;;
esac
