#!/usr/bin/env bats

load test_helper

setup() {
  setup_env
  write_config '{"keys":{"deepl":"secret"}}'
}

@test "free keys use the free endpoint, others the pro endpoint" {
  write_config '{"keys":{"deepl":"abc:fx"}}'
  deepl_reply "привет"
  translate_stdin "hello"
  [ "$(curl_url 1)" = "https://api-free.deepl.com/v2/translate" ]

  write_config '{"keys":{"deepl":"abc"}}'
  rm -rf "$OMARCHY_TRANSLATE_CACHE_DIR"
  deepl_reply "привет"
  translate_stdin "hello"
  [ "$(curl_url 2)" = "https://api.deepl.com/v2/translate" ]
}

@test "the key goes in the Authorization header file and neither key nor text reach argv" {
  deepl_reply "привет"
  translate_stdin "hello"
  [[ "$(curl_headers 1)" == *"Authorization: DeepL-Auth-Key secret"* ]]
  [ "$(curl_headers_mode 1)" = 600 ]
  [[ "$(curl_args 1)" != *secret* ]]
  [[ "$(curl_args 1)" != *Authorization* ]]
  [[ "$(curl_args 1)" != *hello* ]]
  [ "$(jq_field "$(curl_body 1)" '.text[0]')" = hello ]
}

@test "the temporary header file is removed after the request" {
  deepl_reply "привет"
  translate_stdin "hello"
  [ "$status" -eq 0 ]
  [ -z "$(find "$XDG_RUNTIME_DIR" "$TMPDIR" -name 'omarchy-translate-headers.*')" ]
}

@test "the header file falls back to TMPDIR when the runtime dir is unusable" {
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/missing"
  deepl_reply "привет"
  translate_stdin "hello"
  [ "$status" -eq 0 ]
  [[ "$(curl_headers 1)" == *"DeepL-Auth-Key secret"* ]]
  [ -z "$(find "$TMPDIR" -name 'omarchy-translate-headers.*')" ]
}

@test "an API key containing a line break is rejected before curl runs" {
  write_config '{"keys":{"deepl":"abc\nX-Injected: 1"}}'
  translate_stdin "hello"
  [ "$status" -eq 1 ]
  [ "$(jq_field "$output" .error)" = network ]
  [ "$(curl_calls)" -eq 0 ]
}

@test "language codes are converted to DeepL format" {
  deepl_reply "привет" EN
  translate_stdin "hello" --to pt
  [ "$(jq_field "$(curl_body 1)" .target_lang)" = PT-BR ]
  [ "$(jq_field "$(curl_body 1)" '.source_lang // "none"')" = none ]

  deepl_reply "hello" RU
  translate_stdin "привет" --from ru --to en
  [ "$(jq_field "$(curl_body 2)" .target_lang)" = EN-US ]
  [ "$(jq_field "$(curl_body 2)" .source_lang)" = RU ]
}

@test "formality is omitted by default and sent as a prefer_* hint otherwise" {
  deepl_reply "привет"
  translate_stdin "hello"
  [ "$(jq_field "$(curl_body 1)" '.formality // "none"')" = none ]

  write_config '{"keys":{"deepl":"secret"},"deepl_formality":"more"}'
  deepl_reply "здравствуйте"
  translate_stdin "hello again"
  [ "$(jq_field "$(curl_body 2)" .formality)" = prefer_more ]

  write_config '{"keys":{"deepl":"secret"},"deepl_formality":"less"}'
  deepl_reply "привет"
  translate_stdin "hello once more"
  [ "$(jq_field "$(curl_body 3)" .formality)" = prefer_less ]
}

@test "a missing key is no_key without any request" {
  write_config '{}'
  translate_stdin "hello"
  [ "$status" -eq 1 ]
  [ "$(jq_field "$output" .error)" = no_key ]
  [ "$(curl_calls)" -eq 0 ]
}

@test "403 is no_key" {
  curl_reply 403 '{"message":"Forbidden"}'
  translate_stdin "hello"
  [ "$(jq_field "$output" .error)" = no_key ]
}

@test "456 is quota" {
  curl_reply 456 '{"message":"Quota exceeded"}'
  translate_stdin "hello"
  [ "$(jq_field "$output" .error)" = quota ]
}

@test "429 is quota" {
  curl_reply 429 '{"message":"Too many requests"}'
  translate_stdin "hello"
  [ "$(jq_field "$output" .error)" = quota ]
}

@test "transport failures are network errors" {
  curl_fail 6
  translate_stdin "hello"
  [ "$status" -eq 1 ]
  [ "$(jq_field "$output" .error)" = network ]
}

@test "other HTTP errors are network errors with the status" {
  curl_reply 500 '{"message":"boom"}'
  translate_stdin "hello"
  [ "$(jq_field "$output" .error)" = network ]
  [[ "$(jq_field "$output" .message)" == *500* ]]
}

@test "an unexpected response body is a network error" {
  curl_reply 200 '<html>proxy</html>'
  translate_stdin "hello"
  [ "$status" -eq 1 ]
  [ "$(jq_field "$output" .error)" = network ]
}

@test "words get no senses from DeepL" {
  deepl_reply "привет"
  translate_stdin "hello"
  [ "$(jq_field "$output" .kind)" = word ]
  [ "$(jq_field "$output" '.senses | length')" -eq 0 ]
  [ "$(curl_calls)" -eq 1 ]
}
