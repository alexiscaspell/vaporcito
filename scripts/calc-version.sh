#!/usr/bin/env bash
# Calcula la próxima versión semver a partir de los commits desde el último tag estable.
#
# Reglas (la más alta gana):
#   major  – "BREAKING CHANGE", "breaking:", "major:", tipo! (feat!: …), o palabras clave fuertes
#   minor  – feat:, feature:, minor:, "añade"/"agrega"/"rebrand"/"reorganiz" (sin major)
#   patch  – fix:, patch:, chore:, docs:, ci:, refactor:, perf:, o por defecto
#
# Uso:
#   ./scripts/calc-version.sh [--channel develop|main] [--base vX.Y.Z]
#
# Salida (stdout + GITHUB_OUTPUT si existe):
#   version=v1.2.3           # o v1.2.3-develop.<sha7> en develop
#   base=v1.2.0
#   bump=minor
#   channel=main
#   prerelease=false
#
set -euo pipefail

CHANNEL="main"
BASE_OVERRIDE=""
SHA_SHORT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel)
      CHANNEL="${2:-}"
      shift 2
      ;;
    --base)
      BASE_OVERRIDE="${2:-}"
      shift 2
      ;;
    --sha)
      SHA_SHORT="${2:-}"
      shift 2
      ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

case "$CHANNEL" in
  main|develop) ;;
  *)
    echo "channel must be main or develop" >&2
    exit 2
    ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "$SHA_SHORT" ]]; then
  SHA_SHORT="$(git rev-parse --short=7 HEAD)"
fi

# Último tag estable vMAJOR.MINOR.PATCH (sin sufijo prerelease).
last_stable_tag() {
  git tag -l 'v*.*.*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true
}

BASE="${BASE_OVERRIDE}"
if [[ -z "$BASE" ]]; then
  BASE="$(last_stable_tag)"
fi
if [[ -z "$BASE" ]]; then
  BASE="v0.0.0"
fi

if [[ ! "$BASE" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid base version: $BASE (expected vX.Y.Z)" >&2
  exit 1
fi

MAJOR="${BASE#v}"
MAJOR="${MAJOR%%.*}"
REST="${BASE#v*.}"
MINOR="${REST%%.*}"
PATCH="${BASE##*.}"

RANGE_ARGS=()
if git rev-parse -q --verify "$BASE^{commit}" >/dev/null 2>&1; then
  RANGE_ARGS=("${BASE}..HEAD")
else
  # Sin tag real (p.ej. v0.0.0 sintético): todos los commits.
  RANGE_ARGS=("HEAD")
fi

COMMITS="$(git log --pretty=format:'%s' "${RANGE_ARGS[@]}" 2>/dev/null || true)"
BODIES="$(git log --pretty=format:'%b' "${RANGE_ARGS[@]}" 2>/dev/null || true)"
ALL="${COMMITS}"$'\n'"${BODIES}"

bump_from_text() {
  local text="$1"
  local lower
  lower="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"

  # Major
  if printf '%s' "$text" | grep -qiE 'BREAKING CHANGE|^[a-z]+(\([^)]*\))?!:|(^|[[:space:]])breaking:|(^|[[:space:]])major:'; then
    echo major
    return
  fi
  if printf '%s' "$lower" | grep -qiE '\b(breaking|rompe compatibilidad|cambio incompatible|api breaking)\b'; then
    echo major
    return
  fi

  # Minor
  if printf '%s' "$text" | grep -qiE '^(feat|feature|minor)(\([^)]*\))?:'; then
    echo minor
    return
  fi
  if printf '%s' "$lower" | grep -qiE '\b(feat|feature|añade|agrega|agreg[oó]|nueva funcionalidad|rebrand|reorganiz|reordenar)\b'; then
    echo minor
    return
  fi

  # Patch (explícito o default)
  echo patch
}

BUMP="patch"
if [[ -z "$(echo "$COMMITS" | tr -d '[:space:]')" ]]; then
  BUMP="patch"
else
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    case "$(bump_from_text "$line")" in
      major) BUMP="major"; break ;;
      minor) [[ "$BUMP" != "major" ]] && BUMP="minor" ;;
      patch) ;;
    esac
  done <<< "$COMMITS"

  # Bodies can escalate to major (BREAKING CHANGE footer).
  if [[ "$BUMP" != "major" ]] && printf '%s' "$BODIES" | grep -qiE 'BREAKING CHANGE'; then
    BUMP="major"
  fi
fi

case "$BUMP" in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
esac

NEXT="v${MAJOR}.${MINOR}.${PATCH}"

PRERELEASE="false"
VERSION="$NEXT"
if [[ "$CHANNEL" == "develop" ]]; then
  PRERELEASE="true"
  VERSION="${NEXT}-develop.${SHA_SHORT}"
fi

emit() {
  local key="$1"
  local val="$2"
  echo "${key}=${val}"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${val}" >> "$GITHUB_OUTPUT"
  fi
}

emit version "$VERSION"
emit base "$BASE"
emit bump "$BUMP"
emit channel "$CHANNEL"
emit prerelease "$PRERELEASE"
emit next_stable "$NEXT"
