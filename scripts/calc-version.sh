#!/usr/bin/env bash
# Calcula la próxima versión según Semantic Versioning 2.0.0
# (https://semver.org/) a partir de Conventional Commits.
#
# Bump (gana el más alto):
#   MAJOR – BREAKING CHANGE / tipo! (feat!: …)
#   MINOR – feat:
#   PATCH – fix: y resto
#
# Versión (SemVer, sin prefijo v):
#   develop → MAJOR.MINOR.PATCH-develop.N   (ej. 1.0.0-develop.1)
#   main    → MAJOR.MINOR.PATCH             (ej. 1.0.0)
#
# Tag de Git (siempre estable en forma):
#   vMAJOR.MINOR.PATCH   (ej. v1.0.0)  — NUNCA incluye -develop.N
#
# Flujo:
#   develop crea/actualiza una GitHub Release *prerelease* en el tag vM.m.p
#   main promueve el mismo tag a release (sin prerelease)
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
      shift 2
      ;;
    -h|--help)
      sed -n '2,28p' "$0"
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
  local v="$1"
  v="${v#v}"
  # Strip accidental prerelease/build metadata
  v="${v%%-*}"
  v="${v%%+*}"
  if [[ ! "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid SemVer core: $1 (expected MAJOR.MINOR.PATCH)" >&2
    exit 1
  fi
  printf '%s' "$v"
}

tag_exists() {
  local tag="$1"
  git rev-parse -q --verify "refs/tags/${tag}" >/dev/null 2>&1
}

# True if GitHub release for tag is a published non-prerelease (stable).
is_stable_release() {
  local tag="$1"
  if ! command -v gh >/dev/null 2>&1; then
    return 1
  fi
  local json
  json="$(gh release view "$tag" --json isPrerelease,isDraft 2>/dev/null || true)"
  [[ -z "$json" ]] && return 1
  printf '%s' "$json" | grep -q '"isPrerelease":false' || return 1
  printf '%s' "$json" | grep -q '"isDraft":true' && return 1
  return 0
}

# Último core estable: release no-prerelease vía gh, si no tags mergeados en main.
last_stable_core() {
  local t
  if command -v gh >/dev/null 2>&1; then
    t="$(
      gh release list --limit 100 --json tagName,isPrerelease,isDraft \
        --jq '[.[] | select((.isPrerelease|not) and (.isDraft|not)) | .tagName]
              | map(select(test("^v?[0-9]+\\.[0-9]+\\.[0-9]+$")))
              | sort_by(split("v")|last|split(".")|map(tonumber))
              | reverse | .[0] // empty' 2>/dev/null || true
    )"
    if [[ -n "$t" ]]; then
      normalize_core "$t"
      return
    fi
  fi

  for ref in origin/main main; do
    if git rev-parse -q --verify "$ref" >/dev/null 2>&1; then
      t="$(git tag -l 'v*.*.*' --merged "$ref" --sort=-v:refname \
        | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"
      if [[ -n "$t" ]]; then
        normalize_core "$t"
        return
      fi
    fi
  done

  echo "0.0.0"
}

tag_for_core() {
  local core="$1"
  if tag_exists "v${core}"; then
    echo "v${core}"
  elif tag_exists "${core}"; then
    echo "${core}"
  else
    echo ""
  fi
}

BASE_CORE="$(normalize_core "${BASE_OVERRIDE:-$(last_stable_core)}")"
BASE_TAG="$(tag_for_core "$BASE_CORE")"

IFS=. read -r MAJOR MINOR PATCH <<< "$BASE_CORE"

RANGE_ARGS=()
if [[ -n "$BASE_TAG" ]]; then
  RANGE_ARGS=("${BASE_TAG}..HEAD")
else
  RANGE_ARGS=("HEAD")
fi

COMMITS="$(git log --pretty=format:'%s' "${RANGE_ARGS[@]}" 2>/dev/null || true)"
BODIES="$(git log --pretty=format:'%b' "${RANGE_ARGS[@]}" 2>/dev/null || true)"

bump_from_subject() {
  local subject="$1"
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
  if printf '%s' "$subject" | grep -qE '^(chore|docs|ci|refactor|perf|test|style|build|revert)(\([^)]*\))?:'; then
    echo patch
    return
  fi
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

if [[ "$BUMP" != "major" ]] && printf '%s' "$BODIES" | grep -qE '^BREAKING CHANGE([[:space:]]|:|$)' ; then
  BUMP="major"
fi

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

# Primera versión pública
if [[ "$BASE_CORE" == "0.0.0" && -z "$BASE_TAG" ]]; then
  MAJOR=1
  MINOR=0
  PATCH=0
  BUMP="major"
fi

NEXT_CORE="${MAJOR}.${MINOR}.${PATCH}"
TAG="v${NEXT_CORE}"

# Si el tag candidato ya es un release estable, avanzar un patch más.
if is_stable_release "$TAG"; then
  PATCH=$((PATCH + 1))
  NEXT_CORE="${MAJOR}.${MINOR}.${PATCH}"
  TAG="v${NEXT_CORE}"
  BUMP="patch"
fi

# Contador develop.N desde el body de la prerelease (mismo tag vM.m.p).
next_develop_n() {
  local core="$1"
  local tag="v${core}"
  local max=0
  local body n
  if command -v gh >/dev/null 2>&1; then
    body="$(gh release view "$tag" --json body --jq .body 2>/dev/null || true)"
    if [[ "$body" =~ develop_build:[[:space:]]*([0-9]+) ]]; then
      max="${BASH_REMATCH[1]}"
    elif [[ "$body" =~ ${core}-develop\.([0-9]+) ]]; then
      max="${BASH_REMATCH[1]}"
    fi
  fi
  echo $((max + 1))
}

PRERELEASE="false"
VERSION="$NEXT_CORE"
ACTION="create" # create | update-prerelease | promote
DEVELOP_N="0"

if [[ "$CHANNEL" == "develop" ]]; then
  PRERELEASE="true"
  DEVELOP_N="$(next_develop_n "$NEXT_CORE")"
  VERSION="${NEXT_CORE}-develop.${DEVELOP_N}"
  if tag_exists "$TAG"; then
    ACTION="update-prerelease"
  else
    ACTION="create"
  fi
else
  # main: misma versión core (sin -develop), release estable
  PRERELEASE="false"
  VERSION="$NEXT_CORE"
  if is_stable_release "$TAG"; then
    ACTION="skip"
  elif tag_exists "$TAG"; then
    ACTION="promote"
  else
    ACTION="create"
  fi
fi

SKIP="false"
if [[ "$ACTION" == "skip" ]]; then
  SKIP="true"
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
emit tag "$TAG"
emit base "$BASE_CORE"
emit bump "$BUMP"
emit channel "$CHANNEL"
emit prerelease "$PRERELEASE"
emit next_stable "$NEXT_CORE"
emit action "$ACTION"
emit skip "$SKIP"
emit develop_n "$DEVELOP_N"
