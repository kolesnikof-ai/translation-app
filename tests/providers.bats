#!/usr/bin/env bats

load test_helper

setup() {
  setup_env
}

@test "google sends the key in a header and plain-text format" {
  write_config '{"provider":"google","keys":{"google":"gkey"}}'
  curl_reply 200 '{"data":{"translations":[{"translatedText":"привет","detectedSourceLanguage":"en"}]}}'
  translate_stdin "hello"
  [ "$status" -eq 0 ]
  [ "$(curl_url 1)" = "https://translation.googleapis.com/language/translate/v2" ]
  [[ "$(curl_headers 1)" == *"X-goog-api-key: gkey"* ]]
  [[ "$(curl_args 1)" != *gkey* ]]
  [ "$(jq_field "$(curl_body 1)" .q)" = hello ]
  [ "$(jq_field "$(curl_body 1)" .target)" = ru ]
  [ "$(jq_field "$(curl_body 1)" .format)" = text ]
  [ "$(jq_field "$(curl_body 1)" '.source // "none"')" = none ]
  [ "$(jq_field "$output" .detected)" = en ]
  [ "$(jq_field "$output" .provider)" = google ]
  [ "$(jq_field "$output" '.senses | length')" -eq 0 ]
}

@test "google explicit source and error mapping" {
  write_config '{"provider":"google","keys":{"google":"gkey"}}'
  curl_reply 200 '{"data":{"translations":[{"translatedText":"hallo"}]}}'
  translate_stdin "hello" --from EN --to de
  [ "$(jq_field "$(curl_body 1)" .source)" = en ]
  [ "$(jq_field "$output" .detected)" = en ]

  curl_reply 400 '{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}'
  translate_stdin "bye"
  [ "$(jq_field "$output" .error)" = no_key ]

  curl_reply 403 '{"error":{"code":403,"message":"Rate Limit Exceeded","errors":[{"reason":"rateLimitExceeded"}]}}'
  translate_stdin "see you"
  [ "$(jq_field "$output" .error)" = quota ]

  curl_reply 429 '{"error":{"code":429,"message":"Quota exceeded","status":"RESOURCE_EXHAUSTED"}}'
  translate_stdin "later"
  [ "$(jq_field "$output" .error)" = quota ]

  write_config '{"provider":"google"}'
  translate_stdin "no key"
  [ "$(jq_field "$output" .error)" = no_key ]
}

@test "yandex authenticates with an API key only and sends no folder id" {
  write_config '{"provider":"yandex","keys":{"yandex":"ykey"}}'
  curl_reply 200 '{"translations":[{"text":"привет","detectedLanguageCode":"en"}]}'
  translate_stdin "hello"
  [ "$status" -eq 0 ]
  [ "$(curl_url 1)" = "https://translate.api.cloud.yandex.net/translate/v2/translate" ]
  [[ "$(curl_headers 1)" == *"Authorization: Api-Key ykey"* ]]
  [[ "$(curl_args 1)" != *ykey* ]]
  [ "$(jq_field "$(curl_body 1)" .targetLanguageCode)" = ru ]
  [ "$(jq_field "$(curl_body 1)" '.texts[0]')" = hello ]
  [ "$(jq_field "$(curl_body 1)" 'has("folderId")')" = false ]
  [ "$(jq_field "$output" .detected)" = en ]
  [ "$(jq_field "$output" .provider)" = yandex ]
}

@test "yandex errors" {
  write_config '{"provider":"yandex","keys":{"yandex":"ykey"}}'
  curl_reply 401 '{"code":16,"message":"The token is invalid"}'
  translate_stdin "one"
  [ "$(jq_field "$output" .error)" = no_key ]
  curl_reply 429 '{"code":8,"message":"limit"}'
  translate_stdin "two"
  [ "$(jq_field "$output" .error)" = quota ]
  curl_fail 7
  translate_stdin "three"
  [ "$(jq_field "$output" .error)" = network ]
  write_config '{"provider":"yandex"}'
  translate_stdin "four"
  [ "$(jq_field "$output" .error)" = no_key ]
}

@test "libretranslate posts to the configured instance" {
  write_config '{"provider":"libretranslate","libretranslate_url":"https://lt.example.com/","keys":{"libretranslate":"ltkey"}}'
  curl_reply 200 '{"translatedText":"привет","detectedLanguage":{"confidence":90,"language":"en"}}'
  translate_stdin "hello"
  [ "$status" -eq 0 ]
  [ "$(curl_url 1)" = "https://lt.example.com/translate" ]
  [ "$(jq_field "$(curl_body 1)" .source)" = auto ]
  [ "$(jq_field "$(curl_body 1)" .target)" = ru ]
  [ "$(jq_field "$(curl_body 1)" .api_key)" = ltkey ]
  [ "$(jq_field "$output" .detected)" = en ]
  [ "$(jq_field "$output" .provider)" = libretranslate ]
}

@test "libretranslate works without a key and needs a URL" {
  write_config '{"provider":"libretranslate","libretranslate_url":"http://localhost:5000"}'
  curl_reply 200 '{"translatedText":"привет"}'
  translate_stdin "hello"
  [ "$(jq_field "$(curl_body 1)" 'has("api_key")')" = false ]
  [ "$(jq_field "$output" .translation)" = "привет" ]

  write_config '{"provider":"libretranslate"}'
  translate_stdin "hello again"
  [ "$(jq_field "$output" .error)" = no_key ]
}

@test "libretranslate accepts https anywhere and plain http only for this machine" {
  local url
  for url in "https://lt.example.com" "https://lt.example.com:5000/api" "http://localhost" \
    "http://localhost:5000" "http://127.0.0.1:5000" "http://[::1]:5000"; do
    write_config "{\"provider\":\"libretranslate\",\"libretranslate_url\":\"$url\"}"
    rm -rf "$OMARCHY_TRANSLATE_CACHE_DIR"
    curl_reply 200 '{"translatedText":"привет"}'
    translate_stdin "hello"
    [ "$status" -eq 0 ] || { echo "rejected: $url"; return 1; }
  done
}

@test "libretranslate refuses URLs the key must not be sent to" {
  local url
  for url in "http://10.0.0.1:5000" "http://lt.example.com" "http://localhost.evil.example" \
    "http://127.0.0.1.evil.example" "http://localhost:5000@evil.example" \
    "https://user:pass@lt.example.com" "https://user@lt.example.com" \
    "ftp://lt.example.com" "lt.example.com" "https://" "https://lt.example.com/a b" \
    $'https://lt.example.com\nX-Injected: 1'; do
    write_config "$(jq -cn --arg url "$url" '{provider: "libretranslate", libretranslate_url: $url, keys: {libretranslate: "ltkey"}}')"
    translate_stdin "hello"
    [ "$status" -eq 1 ] || { echo "accepted: $url"; return 1; }
    [ "$(jq_field "$output" .error)" = config ] || { echo "wrong error for: $url"; return 1; }
  done
  [ "$(curl_calls)" -eq 0 ]
}

@test "the libretranslate config error does not echo the URL back" {
  write_config '{"provider":"libretranslate","libretranslate_url":"https://user:secretpass@lt.example.com"}'
  translate_stdin "hello"
  [ "$(jq_field "$output" .error)" = config ]
  [[ "$output" != *secretpass* ]]
}

@test "libretranslate error mapping" {
  write_config '{"provider":"libretranslate","libretranslate_url":"http://localhost:5000"}'
  curl_reply 400 '{"error":"Invalid API key"}'
  translate_stdin "one"
  [ "$(jq_field "$output" .error)" = no_key ]
  curl_reply 429 '{"error":"Slowdown: 80 per minute limit exceeded"}'
  translate_stdin "two"
  [ "$(jq_field "$output" .error)" = quota ]
  curl_reply 400 '{"error":"es is not supported"}'
  translate_stdin "three"
  [ "$(jq_field "$output" .error)" = network ]
}

@test "providers without the lookup capability never look words up" {
  local provider
  for provider in google yandex libretranslate deepl; do
    write_config "{\"provider\":\"$provider\",\"libretranslate_url\":\"https://lt.example.com\",\"keys\":{\"google\":\"k\",\"yandex\":\"k\",\"deepl\":\"k\"}}"
    rm -rf "$OMARCHY_TRANSLATE_CACHE_DIR"
    case $provider in
      google) curl_reply 200 '{"data":{"translations":[{"translatedText":"привет","detectedSourceLanguage":"en"}]}}' ;;
      yandex) curl_reply 200 '{"translations":[{"text":"привет","detectedLanguageCode":"en"}]}' ;;
      libretranslate) curl_reply 200 '{"translatedText":"привет","detectedLanguage":{"language":"en"}}' ;;
      deepl) deepl_reply "привет" ;;
    esac
    before=$(curl_calls)
    translate_stdin "hello"
    [ "$status" -eq 0 ]
    [ "$(jq_field "$output" .kind)" = word ]
    [ "$(jq_field "$output" '.senses | length')" -eq 0 ]
    [ "$(( $(curl_calls) - before ))" -eq 1 ]
  done
}

@test "provider hosts cannot be redirected through the environment" {
  export OMARCHY_TRANSLATE_GOOGLE_ENDPOINT=https://evil.example/google
  export OMARCHY_TRANSLATE_MICROSOFT_ENDPOINT=https://evil.example/microsoft
  export OMARCHY_TRANSLATE_YANDEX_ENDPOINT=https://evil.example/yandex
  export GOOGLE_ENDPOINT=https://evil.example/google MICROSOFT_ENDPOINT=https://evil.example/microsoft
  export YANDEX_ENDPOINT=https://evil.example/yandex

  write_config '{"provider":"google","keys":{"google":"k"}}'
  curl_reply 200 '{"data":{"translations":[{"translatedText":"привет","detectedSourceLanguage":"en"}]}}'
  translate_stdin "hello"
  [ "$(curl_url 1)" = "https://translation.googleapis.com/language/translate/v2" ]

  write_config '{"provider":"yandex","keys":{"yandex":"k"}}'
  curl_reply 200 '{"translations":[{"text":"привет","detectedLanguageCode":"en"}]}'
  translate_stdin "hello"
  [ "$(curl_url 2)" = "https://translate.api.cloud.yandex.net/translate/v2/translate" ]

  write_config '{"provider":"microsoft","keys":{"microsoft":"k"}}'
  microsoft_translate_reply "привет"
  translate_stdin "hello world"
  [[ "$(curl_url 3)" == "https://api.cognitive.microsofttranslator.com/translate?"* ]]
}

@test "each request uses exactly the configured provider" {
  write_config '{"provider":"yandex","keys":{"yandex":"y","deepl":"d","google":"g","microsoft":"m"}}'
  curl_reply 200 '{"translations":[{"text":"привет","detectedLanguageCode":"en"}]}'
  translate_stdin "hello"
  [ "$(curl_calls)" -eq 1 ]
  [[ "$(curl_url 1)" == *yandex* ]]
}
