#!/usr/bin/env bats

load test_helper

setup() {
  setup_env
  export OMARCHY_TRANSLATE_BIN_DIR="$BATS_TEST_TMPDIR/bin"
  export OMARCHY_TRANSLATE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg/omarchy/translate"
  export OMARCHY_TRANSLATE_PLUGINS_DIR="$BATS_TEST_TMPDIR/cfg/omarchy/plugins"
  export PATH="$OMARCHY_TRANSLATE_BIN_DIR:$PATH"
}

@test "install links the command and creates a private config" {
  run "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -L "$OMARCHY_TRANSLATE_BIN_DIR/omarchy-translate" ]
  [ "$(readlink "$OMARCHY_TRANSLATE_BIN_DIR/omarchy-translate")" = "$REPO_ROOT/bin/omarchy-translate" ]
  [ "$(stat -c %a "$OMARCHY_TRANSLATE_CONFIG_DIR/config.json")" = 600 ]
  jq -e . "$OMARCHY_TRANSLATE_CONFIG_DIR/config.json" >/dev/null
  [[ "$output" == *'o.bind("SUPER + SHIFT + T"'* ]]
  [[ "$output" == *"omarchy plugin"* ]]
}

@test "the linked command runs" {
  "$REPO_ROOT/install.sh" >/dev/null
  run omarchy-translate --version
  [ "$status" -eq 0 ]
}

@test "install keeps an existing config and tightens its permissions" {
  mkdir -p "$OMARCHY_TRANSLATE_CONFIG_DIR"
  echo '{"target":"de"}' >"$OMARCHY_TRANSLATE_CONFIG_DIR/config.json"
  chmod 644 "$OMARCHY_TRANSLATE_CONFIG_DIR/config.json"
  run "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -r .target "$OMARCHY_TRANSLATE_CONFIG_DIR/config.json")" = de ]
  [ "$(stat -c %a "$OMARCHY_TRANSLATE_CONFIG_DIR/config.json")" = 600 ]
}

@test "install is idempotent" {
  "$REPO_ROOT/install.sh" >/dev/null
  run "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
}

@test "--link-plugin links the checkout under the plugin id" {
  run "$REPO_ROOT/install.sh" --link-plugin
  [ "$status" -eq 0 ]
  [ "$(readlink "$OMARCHY_TRANSLATE_PLUGINS_DIR/translate.lookup")" = "$REPO_ROOT" ]
}

@test "the plugin is not linked unless asked" {
  "$REPO_ROOT/install.sh" >/dev/null
  [ ! -e "$OMARCHY_TRANSLATE_PLUGINS_DIR/translate.lookup" ]
}

@test "--uninstall removes the command link and keeps the config" {
  "$REPO_ROOT/install.sh" >/dev/null
  run "$REPO_ROOT/install.sh" --uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$OMARCHY_TRANSLATE_BIN_DIR/omarchy-translate" ]
  [ -f "$OMARCHY_TRANSLATE_CONFIG_DIR/config.json" ]
}

@test "unknown options are rejected" {
  run "$REPO_ROOT/install.sh" --nope
  [ "$status" -eq 2 ]
}

@test "the example config is valid and matches the built-in defaults" {
  run bash -c 'source "$1/lib/config.sh"; jq -S . <<<"$TR_CONFIG_DEFAULTS"' _ "$REPO_ROOT"
  [ "$status" -eq 0 ]
  diff <(printf '%s\n' "$output") <(jq -S . "$REPO_ROOT/config/config.example.json")
}

@test "the example config uses lowercase language codes and hides the switcher" {
  run jq -e '(.target | test("^[a-z]{2}$")) and (.fallback_target | test("^[a-z]{2}$"))
    and .ui.show_language_switcher == false and .provider == "deepl" and .copy_fallback == false' \
    "$REPO_ROOT/config/config.example.json"
  [ "$status" -eq 0 ]
}
