#!/bin/bash
# Reading the user's text selection. Sourced, never executed.

selection::primary() {
  timeout 1 wl-paste --primary --no-newline --type text 2>/dev/null
}

selection::clipboard() {
  timeout 1 wl-paste --no-newline --type text 2>/dev/null
}

# True when the focused window is a terminal, which copies with Ctrl+Shift+C.
selection::active_is_terminal() {
  command -v hyprctl >/dev/null 2>&1 || return 1
  hyprctl activewindow -j 2>/dev/null \
    | jq -e '(.tags // []) | map(sub("\\*$"; "")) | index("terminal") != null' >/dev/null 2>&1
}

# selection::via_copy -> text copied from the active window with a synthetic
# Ctrl+C. The previous clipboard text is put back afterwards. Fails when the
# clipboard did not change, so a stale clipboard is never mistaken for a
# selection.
selection::via_copy() {
  command -v hyprctl >/dev/null 2>&1 || return 1

  local previous="" had_previous=0 shortcut="CTRL" text="" i
  if previous=$(selection::clipboard); then
    had_previous=1
  fi

  selection::active_is_terminal && shortcut="CTRL SHIFT"

  # Let the hotkey's own modifiers go up before the synthetic chord is sent.
  sleep "${OMARCHY_TRANSLATE_COPY_DELAY:-0.2}"
  hyprctl dispatch sendshortcut "$shortcut, C," >/dev/null 2>&1 || return 1

  for ((i = 0; i < 10; i++)); do
    sleep 0.05
    text=$(selection::clipboard) || text=""
    [[ -n $text && $text != "$previous" ]] && break
  done

  if ((had_previous)); then
    printf '%s' "$previous" | wl-copy
  else
    wl-copy --clear
  fi

  [[ -n $text && $text != "$previous" ]] || return 1
  printf '%s' "$text"
}

# selection::read -> the text to translate, or nothing when there is none.
# Whitespace-only selections count as empty. Needs TR_CONFIG loaded.
selection::read() {
  local text
  text=$(selection::primary) || text=""
  text=$(tr::trim "$text")

  if [[ -z $text && $(config::get '.copy_fallback') == true ]]; then
    text=$(selection::via_copy) || text=""
    text=$(tr::trim "$text")
  fi

  printf '%s' "$text"
}
