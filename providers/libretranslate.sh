#!/bin/bash
# LibreTranslate provider (self-hosted or public instance), translate only.
# Sourced, never executed.

PROVIDER_CAPS="translate"

# libretranslate::fail -> error object for the last response. Instances answer
# a missing or wrong key with 400 or 403, so the message decides.
libretranslate::fail() {
  local message
  message=$(http::message)

  if [[ $HTTP_STATUS == 400 || $HTTP_STATUS == 403 ]] && [[ ${message,,} == *"api key"* || ${message,,} == *"api_key"* ]]; then
    tr::error no_key "LibreTranslate rejected the API key: $message"
  else
    http::fail "LibreTranslate"
  fi
}

provider_translate() {
  local text=$1 src=$2 dst=$3 url key body

  url=$(config::get '.libretranslate_url // ""')
  url=${url%/}
  if [[ -z $url ]]; then
    tr::error no_key "LibreTranslate URL is not set (libretranslate_url in the config)"
    return 1
  fi
  key=$(config::get '.keys.libretranslate // ""')

  body=$(jq -cn --arg text "$text" --arg source "$src" --arg target "$dst" --arg key "$key" '
    {q: $text, source: $source, target: $target, format: "text"}
    + (if $key == "" then {} else {api_key: $key} end)')

  if ! http::post_json "$url/translate" "$body"; then
    http::transport_fail "LibreTranslate"
    return 1
  fi
  if ! http::ok; then
    libretranslate::fail
    return 1
  fi

  http::extract "LibreTranslate" '
    if (.translatedText? // null) == null then error("missing translation") else . end
    | {
        translation: .translatedText,
        detected: ((.detectedLanguage.language? // (if $src == "auto" then "" else $src end))
                   | ascii_downcase | split("-")[0])
      }' --arg src "$src"
}
