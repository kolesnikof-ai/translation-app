#!/usr/bin/env bats

load test_helper

setup() {
  setup_env
  write_config '{"keys":{"deepl":"secret:fx"}}'
}

@test "--stdin prints the normalized JSON result" {
  deepl_reply "привет" EN
  translate_stdin "hello"
  [ "$status" -eq 0 ]
  [ "$(jq_field "$output" .source)" = hello ]
  [ "$(jq_field "$output" .detected)" = en ]
  [ "$(jq_field "$output" .target)" = ru ]
  [ "$(jq_field "$output" .kind)" = word ]
  [ "$(jq_field "$output" .translation)" = "привет" ]
  [ "$(jq_field "$output" .provider)" = deepl ]
  [ "$(jq_field "$output" '.senses | length')" -eq 0 ]
}

@test "--stdin trims the input and rejects empty input" {
  deepl_reply "привет"
  translate_stdin $'  hello \n'
  [ "$(jq_field "$output" .source)" = hello ]

  translate_stdin $' \n '
  [ "$status" -eq 2 ]
}

@test "phrases are classified as phrase" {
  deepl_reply "привет мир"
  translate_stdin "hello world"
  [ "$(jq_field "$output" .kind)" = phrase ]
}

@test "text and language codes are lowercase ISO 639-1 in the JSON" {
  write_config '{"target":"RU","keys":{"deepl":"k"}}'
  deepl_reply "привет" EN
  translate_stdin "hello"
  [ "$(jq_field "$output" .target)" = ru ]
  [ "$(jq_field "$output" .detected)" = en ]
}

@test "text matching the target language falls back to fallback_target" {
  deepl_reply "привет" RU
  deepl_reply "hello" RU
  translate_stdin "привет"
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 2 ]
  [[ "$(curl_body 1)" == *'"target_lang":"RU"'* ]]
  [[ "$(curl_body 2)" == *'"target_lang":"EN-US"'* ]]
  [ "$(jq_field "$output" .target)" = en ]
  [ "$(jq_field "$output" .translation)" = hello ]
}

@test "an explicit --to disables the fallback target" {
  deepl_reply "привет" RU
  translate_stdin "привет" --to ru
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 1 ]
  [ "$(jq_field "$output" .target)" = ru ]
}

@test "--from and --to are normalized and sent to the provider" {
  deepl_reply "Hallo" EN
  translate_stdin "hello" --from EN --to de
  [ "$status" -eq 0 ]
  [[ "$(curl_body 1)" == *'"target_lang":"DE"'* ]]
  [[ "$(curl_body 1)" == *'"source_lang":"EN"'* ]]
}

@test "invalid language codes are a config error" {
  translate_stdin "hello" --to "russian!"
  [ "$status" -eq 1 ]
  [ "$(jq_field "$output" .error)" = config ]
  [ "$(curl_calls)" -eq 0 ]
}

@test "an unknown provider is a config error" {
  write_config '{"provider":"bing"}'
  translate_stdin "hello"
  [ "$status" -eq 1 ]
  [ "$(jq_field "$output" .error)" = config ]
  [[ "$(jq_field "$output" .message)" == *bing* ]]
}

@test "broken config JSON is reported, not ignored" {
  write_config '{not json'
  translate_stdin "hello"
  [ "$status" -eq 1 ]
  [ "$(jq_field "$output" .error)" = config ]
}

@test "missing config file uses defaults and asks for a key" {
  rm -f "$OMARCHY_TRANSLATE_CONFIG"
  translate_stdin "hello"
  [ "$status" -eq 1 ]
  [ "$(jq_field "$output" .error)" = no_key ]
}

@test "unknown options fail with usage" {
  run "$CLI" --bogus
  [ "$status" -eq 2 ]
}

@test "--help and --version work without a config" {
  run "$CLI" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *Usage* ]]
  run "$CLI" --version
  [ "$status" -eq 0 ]
}

@test "the command works through a symlink" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  ln -s "$CLI" "$BATS_TEST_TMPDIR/bin/omarchy-translate"
  deepl_reply "привет"
  run bash -c 'printf hello | "$1" --stdin' _ "$BATS_TEST_TMPDIR/bin/omarchy-translate"
  [ "$status" -eq 0 ]
  [ "$(jq_field "$output" .translation)" = "привет" ]
}

@test "--copy puts the last translation on the clipboard" {
  deepl_reply "привет"
  translate_stdin "hello"
  run "$CLI" --copy
  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_DIR/clipboard")" = "привет" ]
}

@test "--copy without a previous translation fails" {
  run "$CLI" --copy
  [ "$status" -eq 1 ]
}
