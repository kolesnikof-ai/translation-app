#!/usr/bin/env bats

load test_helper

MANIFEST="$REPO_ROOT/manifest.json"

@test "manifest has every field the shell requires" {
  run jq -e '.schemaVersion == 1 and (.id | type == "string") and (.name | type == "string")
    and (.version | type == "string") and (.kinds | type == "array" and length > 0)
    and (.entryPoints | type == "object")' "$MANIFEST"
  [ "$status" -eq 0 ]
}

@test "manifest declares the translate.lookup panel and service" {
  [ "$(jq -r .id "$MANIFEST")" = translate.lookup ]
  [ "$(jq -r '.kinds | sort | join(",")' "$MANIFEST")" = panel,service ]
  [ "$(jq -r .entryPoints.panel "$MANIFEST")" = Panel.qml ]
  [ "$(jq -r .entryPoints.service "$MANIFEST")" = Service.qml ]
}

@test "the plugin id is not in the reserved omarchy namespace" {
  [[ "$(jq -r .id "$MANIFEST")" != omarchy.* ]]
}

@test "entry points are safe relative paths to existing files" {
  local entry
  while IFS= read -r entry; do
    [[ $entry != /* ]]
    [[ $entry != *..* ]]
    [ -f "$REPO_ROOT/$entry" ]
  done < <(jq -r '.entryPoints[]' "$MANIFEST")
}

@test "every kind has a matching entry point" {
  local kind
  while IFS= read -r kind; do
    [ "$(jq -r --arg k "$kind" '.entryPoints[$k] // empty' "$MANIFEST")" != "" ]
  done < <(jq -r '.kinds[]' "$MANIFEST")
}

@test "the stock omarchy plugin validator accepts the plugin when available" {
  command -v omarchy-plugin-validate >/dev/null || skip "omarchy-plugin-validate is not installed"
  run omarchy-plugin-validate "$REPO_ROOT"
  [ "$status" -eq 0 ]
}

@test "the checkout contains no symlinks (omarchy plugin validate rejects them)" {
  run find "$REPO_ROOT" -path "$REPO_ROOT/.git" -prune -o -type l -print
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "all shell scripts pass shellcheck" {
  command -v shellcheck >/dev/null || skip "shellcheck is not installed"
  run shellcheck -x "$REPO_ROOT/bin/omarchy-translate" "$REPO_ROOT"/lib/*.sh "$REPO_ROOT"/providers/*.sh "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
}

@test "QML files parse without syntax errors" {
  local lint=/usr/lib/qt6/bin/qmllint
  command -v qmllint >/dev/null && lint=$(command -v qmllint)
  [ -x "$lint" ] || skip "qmllint is not installed"
  local file
  for file in "$REPO_ROOT"/*.qml; do
    run "$lint" "$file"
    # Unresolved qs.* / Quickshell imports only produce warnings; a real syntax
    # error is reported as "file:line:col: message" without a Warning prefix.
    if echo "$output" | grep -E '^[^ ]+\.qml:[0-9]+:[0-9]+: ' >/dev/null; then
      echo "$file: $output"
      return 1
    fi
  done
}

@test "QML sources only use the documented plugin imports" {
  run grep -hE '^import ' "$REPO_ROOT"/*.qml
  [ "$status" -eq 0 ]
  local line
  while IFS= read -r line; do
    case $line in
      "import QtQuick" | "import QtQuick.Controls" | "import Quickshell" | "import Quickshell.Io" \
        | "import Quickshell.Wayland" | "import qs.Commons" | "import qs.Commons as Commons" | "import qs.Ui" \
        | 'import "PanelModel.js" as Model') ;;
      *) echo "unexpected import: $line"; return 1 ;;
    esac
  done <<<"$output"
}

@test "QML uses the qualified Commons.Color palette" {
  run grep -nE '(^|[^.A-Za-z])Color\.(foreground|background|accent|urgent|popups)' "$REPO_ROOT"/*.qml
  [ "$status" -ne 0 ]
}

@test "Panel.qml implements the panel lifecycle and Service.qml registers the IPC target" {
  grep -q 'function open(payloadJson)' "$REPO_ROOT/Panel.qml"
  grep -q 'function close()' "$REPO_ROOT/Panel.qml"
  grep -q 'target: "translate"' "$REPO_ROOT/Service.qml"
  grep -q 'ShellIpc' "$REPO_ROOT/Service.qml"
}

@test "panel logic helpers behave (node)" {
  command -v node >/dev/null || skip "node is not installed"
  run node "$REPO_ROOT/tests/panel-model.test.js"
  [ "$status" -eq 0 ]
}
