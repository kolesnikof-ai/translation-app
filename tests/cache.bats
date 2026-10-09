#!/usr/bin/env bats

load test_helper

setup() {
  setup_env
  write_config '{"keys":{"deepl":"k"}}'
}

entry_count() {
  find "$OMARCHY_TRANSLATE_CACHE_DIR" -maxdepth 1 -name '*.json' ! -name last.json | wc -l
}

@test "a repeated request is served from the cache without a network call" {
  deepl_reply "привет"
  translate_stdin "hello"
  [ "$(curl_calls)" -eq 1 ]
  translate_stdin "hello"
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 1 ]
  [ "$(jq_field "$output" .translation)" = "привет" ]
}

@test "the cache directory is private and files are named by sha256" {
  deepl_reply "привет"
  translate_stdin "hello"
  [ "$(stat -c %a "$OMARCHY_TRANSLATE_CACHE_DIR")" = 700 ]
  local file
  file=$(find "$OMARCHY_TRANSLATE_CACHE_DIR" -name '*.json' ! -name last.json -printf '%f\n')
  [[ $file =~ ^[0-9a-f]{64}\.json$ ]]
}

@test "different text, language pair or provider miss the cache" {
  deepl_reply "привет"
  translate_stdin "hello"
  deepl_reply "пока"
  translate_stdin "bye"
  deepl_reply "Hallo"
  translate_stdin "hello" --to de
  [ "$(curl_calls)" -eq 3 ]

  write_config '{"provider":"yandex","keys":{"yandex":"y"}}'
  curl_reply 200 '{"translations":[{"text":"привет","detectedLanguageCode":"en"}]}'
  translate_stdin "hello"
  [ "$(curl_calls)" -eq 4 ]
}

@test "changing the DeepL formality misses the cache" {
  deepl_reply "привет"
  translate_stdin "hello"
  write_config '{"keys":{"deepl":"k"},"deepl_formality":"more"}'
  deepl_reply "здравствуйте"
  translate_stdin "hello"
  [ "$(curl_calls)" -eq 2 ]
  [ "$(jq_field "$output" .translation)" = "здравствуйте" ]
}

@test "changing fallback_target misses the cache" {
  deepl_reply "привет" RU
  deepl_reply "hello" RU
  translate_stdin "привет"
  write_config '{"keys":{"deepl":"k"},"fallback_target":"de"}'
  deepl_reply "привет" RU
  deepl_reply "hallo" RU
  translate_stdin "привет"
  [ "$(curl_calls)" -eq 4 ]
  [ "$(jq_field "$output" .target)" = de ]
}

@test "the cached answer keeps the final language pair after a fallback" {
  deepl_reply "привет" RU
  deepl_reply "hello" RU
  translate_stdin "привет"
  translate_stdin "привет"
  [ "$(curl_calls)" -eq 2 ]
  [ "$(jq_field "$output" .target)" = en ]
  [ "$(jq_field "$output" .translation)" = hello ]
}

@test "entries older than 24 hours are refetched" {
  deepl_reply "привет"
  translate_stdin "hello"
  local file
  file=$(find "$OMARCHY_TRANSLATE_CACHE_DIR" -name '*.json' ! -name last.json)
  jq --argjson old "$(($(date +%s) - 90000))" '.cached_at = $old' "$file" >"$file.new"
  mv "$file.new" "$file"

  deepl_reply "здравствуйте"
  translate_stdin "hello"
  [ "$(curl_calls)" -eq 2 ]
  [ "$(jq_field "$output" .translation)" = "здравствуйте" ]
}

@test "fresh entries within the TTL are used" {
  deepl_reply "привет"
  translate_stdin "hello"
  local file
  file=$(find "$OMARCHY_TRANSLATE_CACHE_DIR" -name '*.json' ! -name last.json)
  jq --argjson recent "$(($(date +%s) - 82000))" '.cached_at = $recent' "$file" >"$file.new"
  mv "$file.new" "$file"
  translate_stdin "hello"
  [ "$(curl_calls)" -eq 1 ]
}

@test "only the most recent entries are kept" {
  export OMARCHY_TRANSLATE_CACHE_MAX=3
  local i
  for i in 1 2 3 4 5; do
    deepl_reply "t$i"
    translate_stdin "word$i"
  done
  [ "$(entry_count)" -eq 3 ]
}

@test "the oldest entries are the ones pruned" {
  export OMARCHY_TRANSLATE_CACHE_MAX=2
  deepl_reply "t1"
  translate_stdin "first"
  touch -d "-30 minutes" "$OMARCHY_TRANSLATE_CACHE_DIR"/[0-9a-f]*.json
  deepl_reply "t2"
  translate_stdin "second"
  deepl_reply "t3"
  translate_stdin "third"
  [ "$(entry_count)" -eq 2 ]

  deepl_reply "t1 again"
  translate_stdin "first"
  [ "$(jq_field "$output" .translation)" = "t1 again" ]
}

@test "errors are never cached" {
  curl_reply 456 '{"message":"Quota exceeded"}'
  translate_stdin "hello"
  [ "$(entry_count)" -eq 0 ]
  deepl_reply "привет"
  translate_stdin "hello"
  [ "$(jq_field "$output" .translation)" = "привет" ]
}

@test "the cache keeps the full variant list and the cap applies on output" {
  write_config '{"provider":"microsoft","keys":{"microsoft":"m"},"ui":{"max_variants":1}}'
  microsoft_translate_reply "бежать" en
  curl_reply 200 '[{"translations":[{"displayTarget":"бежать","posTag":"VERB"},{"displayTarget":"работать","posTag":"VERB"}]}]'
  translate_stdin "run"
  [ "$(jq_field "$output" '.senses[0].variants | length')" -eq 1 ]

  write_config '{"provider":"microsoft","keys":{"microsoft":"m"},"ui":{"max_variants":5}}'
  translate_stdin "run"
  [ "$(curl_calls)" -eq 2 ]
  [ "$(jq_field "$output" '.senses[0].variants | length')" -eq 2 ]
}

@test "an unwritable cache location does not break translation" {
  export OMARCHY_TRANSLATE_CACHE_DIR=/proc/nope/cache
  deepl_reply "привет"
  translate_stdin "hello"
  [ "$status" -eq 0 ]
  [ "$(jq_field "$output" .translation)" = "привет" ]
}
