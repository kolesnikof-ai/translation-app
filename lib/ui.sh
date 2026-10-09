#!/bin/bash
# Talking to the panel through omarchy-shell. Sourced, never executed.

TR_PLUGIN_ID="translate.lookup"

# ui::available -> true when the shell CLI is installed.
ui::available() {
  command -v omarchy-shell >/dev/null 2>&1
}

# ui::cursor -> cursor position relative to the monitor it is on, as
# {"x":..,"y":..} in logical pixels, or "null" when it cannot be determined.
ui::cursor() {
  local pos monitors
  command -v hyprctl >/dev/null 2>&1 || { echo null; return 0; }
  pos=$(hyprctl cursorpos -j 2>/dev/null) || { echo null; return 0; }
  monitors=$(hyprctl monitors -j 2>/dev/null) || { echo null; return 0; }

  jq -c --argjson pos "$pos" '
    def logical_width: (if ((.transform // 0) % 2) == 1 then .height else .width end) / (.scale // 1);
    def logical_height: (if ((.transform // 0) % 2) == 1 then .width else .height end) / (.scale // 1);
    ( map(select($pos.x >= .x and $pos.x < (.x + logical_width)
                 and $pos.y >= .y and $pos.y < (.y + logical_height)))
      | first
    ) // (map(select(.focused)) | first) // null
    | if . == null then null
      else {x: (($pos.x - .x) | round), y: (($pos.y - .y) | round)} end
  ' <<<"$monitors" 2>/dev/null || echo null
}

# ui::payload STATE REQUEST_ID TEXT BODY_KEY BODY_JSON CURSOR_JSON
# Builds the JSON the panel understands. BODY_KEY is "result", "error" or "".
ui::payload() {
  local state=$1 request_id=$2 text=$3 body_key=$4 body=$5 cursor=$6
  jq -cn \
    --arg state "$state" \
    --arg request_id "$request_id" \
    --arg text "$text" \
    --arg body_key "$body_key" \
    --argjson body "${body:-null}" \
    --argjson cursor "${cursor:-null}" \
    --argjson config "$TR_CONFIG" '
    {
      state: $state,
      request_id: $request_id,
      source_text: $text,
      source: $config.source,
      target: $config.target,
      ui: $config.ui,
      cursor: $cursor
    }
    + (if $body_key == "" then {} else {($body_key): $body} end)'
}

# ui::summon PAYLOAD -> opens (or re-opens) the panel with PAYLOAD.
# Succeeds when the shell acknowledged the call.
ui::summon() {
  local reply
  reply=$(omarchy-shell shell summon "$TR_PLUGIN_ID" "$1" 2>&1) || {
    tr::notify "omarchy-shell is not running"
    return 1
  }
  if [[ $reply != ok ]]; then
    tr::notify "Plugin $TR_PLUGIN_ID is not enabled. Run: omarchy plugin enable $TR_PLUGIN_ID"
    return 1
  fi
}

# ui::deliver PAYLOAD -> hands a finished result to an open panel. When the
# translate IPC target is missing the panel is re-summoned instead; when the
# user already closed the panel nothing is shown.
ui::deliver() {
  local reply
  if reply=$(omarchy-shell translate show "$1" 2>/dev/null); then
    case $reply in
      ok | closed) return 0 ;;
    esac
  fi
  ui::summon "$1"
}
