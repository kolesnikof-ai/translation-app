#!/bin/bash
# Shared helpers for omarchy-translate. Sourced, never executed.

# tr::error CODE MESSAGE -> prints the normalized error object.
# CODE is one of: no_key, network, quota, config.
tr::error() {
  jq -cn --arg error "$1" --arg message "$2" '{error: $error, message: $message}'
}

# tr::is_error JSON -> succeeds when JSON is an error object.
tr::is_error() {
  jq -e 'type == "object" and has("error")' >/dev/null 2>&1 <<<"$1"
}

# tr::trim TEXT -> TEXT without leading/trailing whitespace.
tr::trim() {
  local text=$1
  text="${text#"${text%%[![:space:]]*}"}"
  text="${text%"${text##*[![:space:]]}"}"
  printf '%s' "$text"
}

# tr::notify MESSAGE -> best-effort desktop notification.
tr::notify() {
  if command -v omarchy-notification-send >/dev/null 2>&1; then
    omarchy-notification-send "Translate" "$1" >/dev/null 2>&1 || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "Translate" "$1" >/dev/null 2>&1 || true
  else
    printf 'omarchy-translate: %s\n' "$1" >&2
  fi
}
