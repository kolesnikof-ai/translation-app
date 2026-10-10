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

# libretranslate::valid_url URL -> succeeds for a URL that is safe to send the
# API key to: https anywhere, or plain http only for this machine (localhost,
# 127.0.0.1, ::1). Whitespace and embedded credentials (user:pass@) are refused.
libretranslate::valid_url() {
  local url=$1 rest authority host

  [[ $url != *[[:space:]]* ]] || return 1
  case $url in
    https://*) rest=${url#https://} ;;
    http://*) rest=${url#http://} ;;
    *) return 1 ;;
  esac

  authority=${rest%%[/?#]*}
  [[ -n $authority && $authority != *@* ]] || return 1

  if [[ $url == http://* ]]; then
    if [[ $authority == \[*\]* ]]; then
      host=${authority%%]*}]
    else
      host=${authority%%:*}
    fi
    case $host in
      localhost | 127.0.0.1 | '[::1]') ;;
      *) return 1 ;;
    esac
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
  if ! libretranslate::valid_url "$url"; then
    # The URL is left out of the message: it may carry credentials.
    tr::error config "libretranslate_url must be an https:// URL without credentials (plain http is only allowed for localhost)"
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
