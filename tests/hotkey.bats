#!/usr/bin/env bats

load test_helper

setup() {
  setup_env
  write_config '{"keys":{"deepl":"k"}}'
}

summons() {
  grep -c '^shell summon translate.lookup ' "$MOCK_DIR/shell.log" || true
}

# summon_payload N -> JSON payload of the Nth summon call.
summon_payload() {
  grep '^shell summon translate.lookup ' "$MOCK_DIR/shell.log" | sed -n "${1}p" | sed 's/^shell summon translate.lookup //'
}

show_payload() {
  grep '^translate show ' "$MOCK_DIR/shell.log" | sed -n "${1}p" | sed 's/^translate show //'
}

@test "a selection opens the panel in loading state, then delivers the result over IPC" {
  printf 'hello' >"$MOCK_DIR/primary"
  deepl_reply "привет"
  run "$CLI"
  [ "$status" -eq 0 ]
  [ "$(summons)" -eq 1 ]
  local loading result
  loading=$(summon_payload 1)
  [ "$(jq_field "$loading" .state)" = loading ]
  [ "$(jq_field "$loading" .source_text)" = hello ]
  [ "$(jq_field "$loading" .ui.position)" = cursor ]
  result=$(show_payload 1)
  [ "$(jq_field "$result" .state)" = result ]
  [ "$(jq_field "$result" .result.translation)" = "привет" ]
  [ "$(jq_field "$result" .request_id)" = "$(jq_field "$loading" .request_id)" ]
}

@test "the summon payload carries cursor position and panel settings" {
  write_config '{"keys":{"deepl":"k"},"ui":{"width":600,"height":300,"show_language_switcher":true,"max_variants":3}}'
  printf 'hello' >"$MOCK_DIR/primary"
  deepl_reply "привет"
  run "$CLI"
  local loading
  loading=$(summon_payload 1)
  [ "$(jq_field "$loading" .cursor.x)" = 100 ]
  [ "$(jq_field "$loading" .cursor.y)" = 200 ]
  [ "$(jq_field "$loading" .ui.width)" = 600 ]
  [ "$(jq_field "$loading" .ui.show_language_switcher)" = true ]
  [ "$(jq_field "$loading" .ui.max_variants)" = 3 ]
  [ "$(jq_field "$loading" .target)" = ru ]
  [ "$(jq_field "$loading" .source)" = auto ]
}

@test "the language switcher is off by default" {
  printf 'hello' >"$MOCK_DIR/primary"
  deepl_reply "привет"
  run "$CLI"
  [ "$(jq_field "$(summon_payload 1)" .ui.show_language_switcher)" = false ]
}

@test "cursor position is made relative to the monitor it is on" {
  cat >"$MOCK_DIR/monitors.json" <<'JSON'
[{"name":"A","x":0,"y":0,"width":1920,"height":1080,"scale":1.0,"transform":0,"focused":false},
 {"name":"B","x":1920,"y":0,"width":3840,"height":2160,"scale":2.0,"transform":0,"focused":true}]
JSON
  echo '{"x": 2520, "y": 300}' >"$MOCK_DIR/cursorpos.json"
  printf 'hello' >"$MOCK_DIR/primary"
  deepl_reply "привет"
  run "$CLI"
  [ "$(jq_field "$(summon_payload 1)" .cursor.x)" = 600 ]
  [ "$(jq_field "$(summon_payload 1)" .cursor.y)" = 300 ]
}

@test "no hyprctl means no cursor position" {
  printf 'hello' >"$MOCK_DIR/primary"
  deepl_reply "привет"
  run env PATH="$BATS_TEST_TMPDIR/nohypr:$PATH" bash -c '
    mkdir -p "$1/nohypr"; for c in curl wl-paste wl-copy omarchy-shell; do ln -sf "$2/tests/mocks/$c" "$1/nohypr/$c"; done
    PATH="$1/nohypr:/usr/bin:/bin" "$3"' _ "$BATS_TEST_TMPDIR" "$REPO_ROOT" "$CLI"
  [ "$(jq_field "$(summon_payload 1)" .cursor)" = null ]
}

@test "an empty selection opens input mode without translating" {
  run "$CLI"
  [ "$status" -eq 0 ]
  [ "$(summons)" -eq 1 ]
  [ "$(jq_field "$(summon_payload 1)" .state)" = input ]
  [ "$(curl_calls)" -eq 0 ]
}

@test "a whitespace-only selection counts as empty" {
  printf ' \n\t ' >"$MOCK_DIR/primary"
  run "$CLI"
  [ "$(jq_field "$(summon_payload 1)" .state)" = input ]
  [ "$(curl_calls)" -eq 0 ]
}

@test "--input ignores the selection" {
  printf 'hello' >"$MOCK_DIR/primary"
  run "$CLI" --input
  [ "$(jq_field "$(summon_payload 1)" .state)" = input ]
  [ "$(curl_calls)" -eq 0 ]
}

@test "multi-line selections are translated as phrases" {
  printf 'line one\nline two' >"$MOCK_DIR/primary"
  deepl_reply "перевод"
  run "$CLI"
  [ "$(jq_field "$(show_payload 1)" .result.kind)" = phrase ]
  [ "$(jq_field "$(show_payload 1)" .result.source)" = $'line one\nline two' ]
}

@test "errors are delivered to the panel as an error state" {
  printf 'hello' >"$MOCK_DIR/primary"
  curl_reply 456 '{"message":"Quota exceeded"}'
  run "$CLI"
  [ "$status" -eq 1 ]
  [ "$(jq_field "$(show_payload 1)" .state)" = error ]
  [ "$(jq_field "$(show_payload 1)" .error.error)" = quota ]
}

@test "a broken config is shown in the panel" {
  write_config '{oops'
  printf 'hello' >"$MOCK_DIR/primary"
  run "$CLI"
  [ "$status" -eq 1 ]
  [ "$(jq_field "$(summon_payload 1)" .state)" = error ]
  [ "$(jq_field "$(summon_payload 1)" .error.error)" = config ]
}

@test "when the translate IPC target is missing the result is delivered by summon" {
  export MOCK_SHOW_FAIL=1
  printf 'hello' >"$MOCK_DIR/primary"
  deepl_reply "привет"
  run "$CLI"
  [ "$(summons)" -eq 2 ]
  [ "$(jq_field "$(summon_payload 2)" .state)" = result ]
}

@test "a closed panel is not reopened when the result arrives" {
  export MOCK_SHOW_REPLY=closed
  printf 'hello' >"$MOCK_DIR/primary"
  deepl_reply "привет"
  run "$CLI"
  [ "$(summons)" -eq 1 ]
}

@test "a disabled plugin produces a notification instead of a panel" {
  export MOCK_SUMMON_REPLY=unknown
  printf 'hello' >"$MOCK_DIR/primary"
  run "$CLI"
  [ "$status" -eq 1 ]
  [[ "$(cat "$MOCK_DIR/notify.log")" == *"omarchy plugin enable translate.lookup"* ]]
  [ "$(curl_calls)" -eq 0 ]
}

@test "copy_fallback copies from the active window and restores the clipboard" {
  write_config '{"keys":{"deepl":"k"},"copy_fallback":true}'
  printf 'previous clipboard' >"$MOCK_DIR/clipboard"
  printf 'copied text' >"$MOCK_DIR/copy-result"
  deepl_reply "скопированный текст"
  run "$CLI"
  [ "$status" -eq 0 ]
  [ "$(jq_field "$(summon_payload 1)" .source_text)" = "copied text" ]
  [ "$(cat "$MOCK_DIR/hyprctl.log")" = "sendshortcut CTRL, C," ]
  [ "$(cat "$MOCK_DIR/clipboard")" = "previous clipboard" ]
}

@test "copy_fallback uses Ctrl+Shift+C in terminals" {
  write_config '{"keys":{"deepl":"k"},"copy_fallback":true}'
  echo '{"tags":["terminal*"]}' >"$MOCK_DIR/activewindow.json"
  printf 'copied text' >"$MOCK_DIR/copy-result"
  deepl_reply "x"
  run "$CLI"
  [ "$(cat "$MOCK_DIR/hyprctl.log")" = "sendshortcut CTRL SHIFT, C," ]
}

@test "copy_fallback is not used while the primary selection has text" {
  write_config '{"keys":{"deepl":"k"},"copy_fallback":true}'
  printf 'selected' >"$MOCK_DIR/primary"
  deepl_reply "x"
  run "$CLI"
  [ ! -e "$MOCK_DIR/hyprctl.log" ]
  [ "$(jq_field "$(summon_payload 1)" .source_text)" = selected ]
}

@test "copy_fallback with an unchanged clipboard opens input mode" {
  write_config '{"keys":{"deepl":"k"},"copy_fallback":true}'
  printf 'same' >"$MOCK_DIR/clipboard"
  run "$CLI"
  [ "$(jq_field "$(summon_payload 1)" .state)" = input ]
  [ "$(cat "$MOCK_DIR/clipboard")" = same ]
}

@test "copy_fallback is off by default" {
  printf 'copied text' >"$MOCK_DIR/copy-result"
  run "$CLI"
  [ ! -e "$MOCK_DIR/hyprctl.log" ]
  [ "$(jq_field "$(summon_payload 1)" .state)" = input ]
}
