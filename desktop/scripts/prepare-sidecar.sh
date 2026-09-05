#!/usr/bin/env bash
# Copy / build the Go engine into src-tauri/binaries with the Tauri sidecar name.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DESKTOP="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$DESKTOP/src-tauri/binaries"
mkdir -p "$BIN_DIR"

TARGET="${1:-native}"

host_triple() {
  rustc -Vv | awk '/^host:/{print $2; exit}'
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

build_go_linux() {
  local out="$ROOT/vaporcito"
  if [[ ! -x "$out" ]]; then
    echo "Building Linux Go binary via Docker..."
    docker run --rm \
      -v "$ROOT":/src \
      -w /src \
      -e CGO_ENABLED=0 \
      -e GOFLAGS=-buildvcs=false \
      -u "$(id -u):$(id -g)" \
      -e HOME=/tmp \
      golang:1.22-bookworm \
      bash -c 'git config --global --add safe.directory /src && go run build.go -goos linux -goarch amd64 -no-upgrade -version v1.0.0-vaporcito build'
  else
    echo "Reusing existing $out"
  fi
  copy_named "$out" "x86_64-unknown-linux-gnu"
}

build_go_windows() {
  echo "Building Windows Go binary via Docker..."
  docker run --rm \
    -v "$ROOT":/src \
    -w /src \
    -e CGO_ENABLED=0 \
    -e GOFLAGS=-buildvcs=false \
    -u "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    golang:1.22-bookworm \
    bash -c 'git config --global --add safe.directory /src && go run build.go -goos windows -goarch amd64 -no-upgrade -version v1.0.0-vaporcito build'
  copy_named "$ROOT/vaporcito.exe" "x86_64-pc-windows-msvc"
}

case "$TARGET" in
  native|linux)
    # Prefer matching the local Rust host triple when on Linux.
    if [[ "$(uname -s)" == "Linux" ]]; then
      build_go_linux
      # Also alias to the exact host triple if it differs.
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
