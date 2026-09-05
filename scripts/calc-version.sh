#!/usr/bin/env bash
# Calcula la próxima versión según Semantic Versioning 2.0.0
# (https://semver.org/) a partir de Conventional Commits desde el último
# release estable.
#
# Bump (gana el más alto):
#   MAJOR – BREAKING CHANGE en el body, o tipo con '!' (ej. feat!: …)
#   MINOR – feat:
#   PATCH – fix: / resto (chore, docs, ci, refactor, perf, test, style, …)
#
# Formato de versión (SemVer puro, sin prefijo v):
#   main     → MAJOR.MINOR.PATCH          (ej. 1.2.3)
#   develop  → MAJOR.MINOR.PATCH-develop.N  (ej. 1.2.3-develop.1)
#
# El tag de Git/GitHub es "v" + version (convención habitual).
#
# Uso:
#   ./scripts/calc-version.sh --channel develop|main [--base X.Y.Z|vX.Y.Z]
#
set -euo pipefail

CHANNEL="main"
BASE_OVERRIDE=""

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
      # Compat: ignorado. Los prereleases usan contador SemVer, no el SHA.
      shift 2
      ;;
    -h|--help)
      sed -n '2,22p' "$0"
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

normalize_core() {
  # Acepta X.Y.Z o vX.Y.Z → imprime X.Y.Z
  local v="$1"
  v="${v#v}"
  if [[ ! "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid SemVer core: $1 (expected MAJOR.MINOR.PATCH)" >&2
    exit 1
  fi
  printf '%s' "$v"
}

# Último tag estable: vMAJOR.MINOR.PATCH o MAJOR.MINOR.PATCH (sin prerelease).
last_stable_core() {
  local t
  t="$(git tag -l --sort=-v:refname | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"
  if [[ -z "$t" ]]; then
    echo "0.0.0"
    return
  fi
  normalize_core "$t"
}

tag_for_ref() {
  # Devuelve un ref de tag existente para un core X.Y.Z (con o sin v).
  local core="$1"
  if git rev-parse -q --verify "refs/tags/v${core}" >/dev/null 2>&1; then
    echo "v${core}"
  elif git rev-parse -q --verify "refs/tags/${core}" >/dev/null 2>&1; then
    echo "${core}"
  else
    echo ""
  fi
}

BASE_CORE="$(normalize_core "${BASE_OVERRIDE:-$(last_stable_core)}")"
BASE_TAG="$(tag_for_ref "$BASE_CORE")"

IFS=. read -r MAJOR MINOR PATCH <<< "$BASE_CORE"

RANGE_ARGS=()
if [[ -n "$BASE_TAG" ]]; then
  RANGE_ARGS=("${BASE_TAG}..HEAD")
else
  RANGE_ARGS=("HEAD")
fi

COMMITS="$(git log --pretty=format:'%s' "${RANGE_ARGS[@]}" 2>/dev/null || true)"
BODIES="$(git log --pretty=format:'%b' "${RANGE_ARGS[@]}" 2>/dev/null || true)"

# Conventional Commits → SemVer (sin heurísticas de lenguaje natural).
bump_from_subject() {
  local subject="$1"
  # type(scope)!: or type!:
  if printf '%s' "$subject" | grep -qE '^[a-zA-Z]+(\([^)]*\))?!:'; then
    echo major
    return
  fi
  if printf '%s' "$subject" | grep -qE '^feat(\([^)]*\))?:'; then
    echo minor
    return
  fi
  if printf '%s' "$subject" | grep -qE '^fix(\([^)]*\))?:'; then
    echo patch
    return
  fi
  # Otros tipos convencionales → patch
  if printf '%s' "$subject" | grep -qE '^(chore|docs|ci|refactor|perf|test|style|build|revert)(\([^)]*\))?:'; then
    echo patch
    return
  fi
  # Commits no convencionales → patch
  echo patch
}

BUMP="none"
if [[ -n "$(printf '%s' "$COMMITS" | tr -d '[:space:]')" ]]; then
  BUMP="patch"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    case "$(bump_from_subject "$line")" in
      major) BUMP="major"; break ;;
      minor) [[ "$BUMP" != "major" ]] && BUMP="minor" ;;
      patch) [[ "$BUMP" == "none" ]] && BUMP="patch" ;;
    esac
  done <<< "$COMMITS"
fi

# Footer Conventional Commits
if [[ "$BUMP" != "major" ]] && printf '%s' "$BODIES" | grep -qE '^BREAKING CHANGE([[:space:]]|:|$)' ; then
  BUMP="major"
fi

# Sin commits nuevos desde el tag estable: en main no hay nada que publicar
# con bump real; en develop igual se permite un patch prerelease sobre NEXT.
if [[ "$BUMP" == "none" ]]; then
  BUMP="patch"
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

# Sin tags previos: primera versión pública SemVer = 1.0.0
if [[ "$BASE_CORE" == "0.0.0" && -z "$BASE_TAG" ]]; then
  MAJOR=1
  MINOR=0
  PATCH=0
  BUMP="major"
fi

NEXT_CORE="${MAJOR}.${MINOR}.${PATCH}"

# Próximo contador develop.N (identificador numérico = orden SemVer correcto).
next_develop_n() {
  local core="$1"
  local max=0
  local t n
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    n="${t##*-develop.}"
    n="${n#v}"
    if [[ "$n" =~ ^[0-9]+$ ]] && (( n > max )); then
      max=$n
    fi
  done < <(git tag -l "v${core}-develop.*" "${core}-develop.*" 2>/dev/null || true)
  echo $((max + 1))
}

PRERELEASE="false"
VERSION="$NEXT_CORE"
if [[ "$CHANNEL" == "develop" ]]; then
  PRERELEASE="true"
  N="$(next_develop_n "$NEXT_CORE")"
  VERSION="${NEXT_CORE}-develop.${N}"
fi

TAG="v${VERSION}"

emit() {
  local key="$1"
  local val="$2"
  echo "${key}=${val}"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${val}" >> "$GITHUB_OUTPUT"
  fi
}

emit version "$VERSION"
emit tag "$TAG"
emit base "$BASE_CORE"
emit bump "$BUMP"
emit channel "$CHANNEL"
emit prerelease "$PRERELEASE"
emit next_stable "$NEXT_CORE"
