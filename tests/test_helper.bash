#!/bin/bash
# Shared bats setup: an isolated HOME, mocked external commands on PATH and
# helpers to queue curl replies and inspect what was sent.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
CLI="$REPO_ROOT/bin/omarchy-translate"

setup_env() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  export MOCK_CURL_DIR="$MOCK_DIR/curl"
  export OMARCHY_TRANSLATE_CONFIG="$BATS_TEST_TMPDIR/config.json"
  export OMARCHY_TRANSLATE_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  export OMARCHY_TRANSLATE_COPY_DELAY=0
  mkdir -p "$HOME" "$MOCK_CURL_DIR"
  export PATH="$REPO_ROOT/tests/mocks:$PATH"
  CURL_REPLIES=0
}

# write_config JSON -> replaces the user config.
write_config() {
  printf '%s' "$1" >"$OMARCHY_TRANSLATE_CONFIG"
}

# curl_reply STATUS BODY -> queues the next mocked HTTP response.
curl_reply() {
  CURL_REPLIES=$((CURL_REPLIES + 1))
  printf '%s' "$1" >"$MOCK_CURL_DIR/reply.$CURL_REPLIES.status"
  printf '%s' "$2" >"$MOCK_CURL_DIR/reply.$CURL_REPLIES.body"
}

# curl_fail EXIT_CODE -> queues a transport failure.
curl_fail() {
  CURL_REPLIES=$((CURL_REPLIES + 1))
  printf '%s' "$1" >"$MOCK_CURL_DIR/reply.$CURL_REPLIES.exit"
}

curl_calls() {
  cat "$MOCK_CURL_DIR/calls" 2>/dev/null || echo 0
}

# curl_args N -> the arguments of call N, space separated.
curl_args() {
  tr '\n' ' ' <"$MOCK_CURL_DIR/call.$1.args"
}

curl_url() {
  tail -n 1 "$MOCK_CURL_DIR/call.$1.args"
}

curl_body() {
  cat "$MOCK_CURL_DIR/call.$1.body"
}

# translate_stdin TEXT [ARGS...] -> runs the CLI in --stdin mode.
translate_stdin() {
  local text=$1
  shift
  run bash -c 'printf %s "$1" | "$2" --stdin "${@:3}"' _ "$text" "$CLI" "$@"
}

# jq_field JSON FILTER
jq_field() {
  jq -r "$2" <<<"$1"
}

deepl_reply() {
  curl_reply 200 "{\"translations\":[{\"detected_source_language\":\"${2:-EN}\",\"text\":\"$1\"}]}"
}

microsoft_translate_reply() {
  curl_reply 200 "[{\"detectedLanguage\":{\"language\":\"${2:-en}\",\"score\":1.0},\"translations\":[{\"text\":\"$1\",\"to\":\"ru\"}]}]"
}
