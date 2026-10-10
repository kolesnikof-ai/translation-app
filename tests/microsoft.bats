#!/usr/bin/env bats

load test_helper

setup() {
  setup_env
  write_config '{"provider":"microsoft","keys":{"microsoft":"mskey","microsoft_region":"westeurope"}}'
}

lookup_reply() {
  curl_reply 200 '[{"normalizedSource":"run","translations":[
    {"normalizedTarget":"бежать","displayTarget":"бежать","posTag":"VERB","confidence":0.5},
    {"normalizedTarget":"бег","displayTarget":"бег","posTag":"NOUN","confidence":0.3},
    {"normalizedTarget":"работать","displayTarget":"работать","posTag":"VERB","confidence":0.2},
    {"normalizedTarget":"бежать","displayTarget":"бежать","posTag":"VERB","confidence":0.1},
    {"normalizedTarget":"управлять","displayTarget":"управлять","posTag":"VERB","confidence":0.1},
    {"normalizedTarget":"идти","displayTarget":"идти","posTag":"VERB","confidence":0.1},
    {"normalizedTarget":"ходить","displayTarget":"ходить","posTag":"VERB","confidence":0.1},
    {"normalizedTarget":"быстрый","displayTarget":"быстрый","posTag":"ADJ","confidence":0.1}
  ]}]'
}

@test "translate request carries key, region and language pair" {
  microsoft_translate_reply "привет"
  translate_stdin "hello world"
  [ "$status" -eq 0 ]
  [[ "$(curl_url 1)" == "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&textType=plain&to=ru" ]]
  [[ "$(curl_headers 1)" == *"Ocp-Apim-Subscription-Key: mskey"* ]]
  [[ "$(curl_headers 1)" == *"Ocp-Apim-Subscription-Region: westeurope"* ]]
  [ "$(curl_headers_mode 1)" = 600 ]
  [[ "$(curl_args 1)" != *mskey* ]]
  [ "$(jq_field "$(curl_body 1)" '.[0].Text')" = "hello world" ]
}

@test "an explicit source adds from= and Chinese maps to zh-Hans" {
  microsoft_translate_reply "你好" en
  translate_stdin "hello world" --from en --to zh
  [[ "$(curl_url 1)" == *"to=zh-Hans"* ]]
  [[ "$(curl_url 1)" == *"from=en"* ]]
}

@test "the region header is omitted when no region is configured" {
  write_config '{"provider":"microsoft","keys":{"microsoft":"mskey"}}'
  microsoft_translate_reply "привет"
  translate_stdin "hello world"
  [[ "$(curl_headers 1)" != *Region* ]]
}

@test "a key containing a line break is rejected instead of splitting into two headers" {
  write_config '{"provider":"microsoft","keys":{"microsoft":"mskey\nX-Injected: 1"}}'
  translate_stdin "hello world"
  [ "$status" -eq 1 ]
  [ "$(jq_field "$output" .error)" = network ]
  [ "$(curl_calls)" -eq 0 ]
}

@test "a word triggers a dictionary lookup with the detected language" {
  microsoft_translate_reply "бежать" en
  lookup_reply
  translate_stdin "run"
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 2 ]
  [ "$(curl_url 2)" = "https://api.cognitive.microsofttranslator.com/dictionary/lookup?api-version=3.0&from=en&to=ru" ]
  [ "$(jq_field "$(curl_body 2)" '.[0].Text')" = run ]
  [ "$(jq_field "$output" .kind)" = word ]
}

@test "senses are grouped by part of speech in provider order without duplicates" {
  write_config '{"provider":"microsoft","keys":{"microsoft":"mskey"},"ui":{"max_variants":50}}'
  microsoft_translate_reply "бежать" en
  lookup_reply
  translate_stdin "run"
  [ "$(jq_field "$output" '.senses | map(.pos) | join(",")')" = "verb,noun,adjective" ]
  [ "$(jq_field "$output" '.senses[0].variants | join(",")')" = "бежать,работать,управлять,идти,ходить" ]
  [ "$(jq_field "$output" '.senses[1].variants | join(",")')" = "бег" ]
}

@test "variants per part of speech are capped by ui.max_variants" {
  write_config '{"provider":"microsoft","keys":{"microsoft":"mskey"},"ui":{"max_variants":2}}'
  microsoft_translate_reply "бежать" en
  lookup_reply
  translate_stdin "run"
  [ "$(jq_field "$output" '.senses[0].variants | join(",")')" = "бежать,работать" ]
}

@test "the default cap is 5 variants" {
  microsoft_translate_reply "бежать" en
  lookup_reply
  translate_stdin "run"
  [ "$(jq_field "$output" '.senses[0].variants | length')" -eq 5 ]
}

@test "senses carry no examples, transcription or extra fields" {
  microsoft_translate_reply "бежать" en
  lookup_reply
  translate_stdin "run"
  [ "$(jq_field "$output" '.senses[0] | keys | join(",")')" = "pos,variants" ]
}

@test "phrases never trigger a lookup" {
  microsoft_translate_reply "бегите быстро" en
  translate_stdin "run fast"
  [ "$(curl_calls)" -eq 1 ]
  [ "$(jq_field "$output" '.senses | length')" -eq 0 ]
}

@test "a failed lookup keeps the translation and drops the senses" {
  microsoft_translate_reply "бежать" en
  curl_reply 400 '{"error":{"code":400000,"message":"pair not supported"}}'
  translate_stdin "run"
  [ "$status" -eq 0 ]
  [ "$(jq_field "$output" .translation)" = "бежать" ]
  [ "$(jq_field "$output" '.senses | length')" -eq 0 ]
}

@test "no lookup when the word is already in the target language and falls back" {
  microsoft_translate_reply "привет" ru
  microsoft_translate_reply "hello" ru
  curl_reply 200 '[{"translations":[{"displayTarget":"hello","posTag":"NOUN"}]}]'
  translate_stdin "привет"
  [ "$(jq_field "$output" .target)" = en ]
  [ "$(curl_url 3)" = "https://api.cognitive.microsofttranslator.com/dictionary/lookup?api-version=3.0&from=ru&to=en" ]
  [ "$(jq_field "$output" '.senses[0].variants[0]')" = hello ]
}

@test "missing key is no_key" {
  write_config '{"provider":"microsoft"}'
  translate_stdin "hello"
  [ "$(jq_field "$output" .error)" = no_key ]
}

@test "401 is no_key and 429 is quota" {
  curl_reply 401 '{"error":{"code":401000,"message":"bad key"}}'
  translate_stdin "hello world"
  [ "$(jq_field "$output" .error)" = no_key ]
  curl_reply 429 '{"error":{"code":429001,"message":"slow down"}}'
  translate_stdin "hello again"
  [ "$(jq_field "$output" .error)" = quota ]
}

@test "403 with a 4030xx code is quota" {
  curl_reply 403 '{"error":{"code":403001,"message":"The subscription has exceeded its free quota."}}'
  translate_stdin "hello world"
  [ "$(jq_field "$output" .error)" = quota ]
}

@test "a different provider is never consulted" {
  microsoft_translate_reply "привет"
  translate_stdin "hello world"
  [[ "$(curl_url 1)" != *deepl* ]]
  [ "$(curl_calls)" -eq 1 ]
}
