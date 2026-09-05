#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Repo root helpers live here; Go module build runs from back/.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACK="$ROOT/back"
cd "$BACK"

script() {
	name="$1"
	shift
	go run "scripts/$name.go" "$@"
}

build() {
	go run build.go "$@"
}

case "${1:-default}" in
	test)
		LOGGER_DISCARD=1 build test
		;;

	bench)
		LOGGER_DISCARD=1 build bench
		;;

	prerelease)
		script authors
		build weblate
		pushd man ; ./refresh.sh ; popd
		git add -A "$ROOT/front/gui" man "$ROOT/AUTHORS"
		git commit -m 'gui, man, authors: Update docs, translations, and contributors'
		;;

	*)
		build "$@"
		;;
esac
