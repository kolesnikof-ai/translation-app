#!/bin/bash
# On-disk translation cache. Sourced, never executed.
#
# One file per request, named after the sha256 of everything that influences
# the answer. Entries expire after 24 hours and only the 500 most recently
# used ones are kept. All failures are silent: the cache is an optimization.

CACHE_TTL="${OMARCHY_TRANSLATE_CACHE_TTL:-86400}"
CACHE_MAX="${OMARCHY_TRANSLATE_CACHE_MAX:-500}"

cache::dir() {
  printf '%s' "${OMARCHY_TRANSLATE_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-translate}"
}

# cache::ensure_dir -> creates the cache directory, private from the first
# moment: the umask keeps mkdir from ever leaving it open to other users, and
# the chmod tightens a directory an older version created.
cache::ensure_dir() {
  local dir
  dir=$(cache::dir)
  (umask 077 && mkdir -p "$dir") 2>/dev/null && chmod 700 "$dir" 2>/dev/null
}

# cache::write_private FILE CONTENT -> replaces FILE atomically. The new file
# comes from mktemp, so it is readable by its owner only (mode 0600) even when
# FILE existed with wider permissions.
cache::write_private() {
  local file=$1 tmp
  tmp=$(mktemp "$(dirname "$file")/.tmp.XXXXXX" 2>/dev/null) || return 1
  if printf '%s\n' "$2" >"$tmp" 2>/dev/null && mv -f "$tmp" "$file" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# cache::key PROVIDER SRC DST EXTRA TEXT -> sha256 hex digest.
cache::key() {
  printf '%s\0' "$@" | sha256sum | cut -d' ' -f1
}

# cache::get KEY -> prints the cached result when it exists and is fresh.
cache::get() {
  local file now entry
  file="$(cache::dir)/$1.json"
  [[ -f $file ]] || return 1

  now=$(date +%s)
  entry=$(jq -c --argjson now "$now" --argjson ttl "$CACHE_TTL" '
    select(($now - .cached_at) < $ttl) | .result' "$file" 2>/dev/null) || return 1
  [[ -n $entry ]] || return 1

  touch "$file" 2>/dev/null
  printf '%s' "$entry"
}

# cache::put KEY RESULT_JSON
cache::put() {
  local dir tmp
  cache::ensure_dir || return 0
  dir=$(cache::dir)

  tmp=$(mktemp "$dir/.tmp.XXXXXX" 2>/dev/null) || return 0
  if jq -cn --argjson now "$(date +%s)" --argjson result "$2" '{cached_at: $now, result: $result}' >"$tmp" 2>/dev/null; then
    mv -f "$tmp" "$dir/$1.json" 2>/dev/null || rm -f "$tmp"
  else
    rm -f "$tmp"
  fi
  cache::prune
}

# cache::prune -> drops everything but the CACHE_MAX most recently used entries.
cache::prune() {
  local dir stale
  dir=$(cache::dir)
  while IFS= read -r stale; do
    rm -f "${dir:?}/$stale"
  done < <(find "$dir" -maxdepth 1 -type f -regextype posix-extended -regex '.*/[0-9a-f]{64}\.json' \
    -printf '%T@ %f\n' 2>/dev/null | sort -rn | tail -n +"$((CACHE_MAX + 1))" | cut -d' ' -f2)
}

# cache::save_last RESULT_JSON -> remembers the latest translation for --copy.
cache::save_last() {
  cache::ensure_dir || return 0
  cache::write_private "$(cache::dir)/last.json" "$1" || true
}

# cache::last_translation -> the translation text from the latest result.
cache::last_translation() {
  jq -er '.translation' "$(cache::dir)/last.json" 2>/dev/null
}
