#!/bin/bash
# Google Cloud Translation (Basic, v2) provider, translate only.
# Sourced, never executed.

PROVIDER_CAPS="translate"

GOOGLE_ENDPOINT="${OMARCHY_TRANSLATE_GOOGLE_ENDPOINT:-https://translation.googleapis.com/language/translate/v2}"

# google::fail -> error object for the last response. Google reports quota
# problems as 403 or 429 with a reason, and bad keys as 400 or 403.
google::fail() {
  local reason message
  reason=$(jq -r '[.error.errors[0].reason?, .error.status?] | map(select(. != null)) | join(" ")' <<<"$HTTP_BODY" 2>/dev/null)
  message=$(http::message)

  case $reason in
    *rateLimitExceeded* | *dailyLimitExceeded* | *quotaExceeded* | *userRateLimitExceeded* | *RESOURCE_EXHAUSTED*)
      tr::error quota "Google Translate quota exceeded${message:+: $message}"
      return
      ;;
    *keyInvalid* | *API_KEY_INVALID* | *badRequest*API*key*)
      tr::error no_key "Google Translate rejected the API key${message:+: $message}"
      return
      ;;
  esac

  if [[ $HTTP_STATUS == 400 && $message == *"API key"* ]]; then
    tr::error no_key "Google Translate rejected the API key: $message"
  else
    http::fail "Google Translate"
  fi
}

provider_translate() {
  local text=$1 src=$2 dst=$3 key body

  key=$(config::get '.keys.google // ""')
  if [[ -z $key ]]; then
    tr::error no_key "Google Translate API key is not set (keys.google in the config)"
    return 1
  fi

  body=$(jq -cn --arg text "$text" --arg target "$dst" --arg source "$([[ $src == auto ]] || printf '%s' "$src")" '
    {q: $text, target: $target, format: "text"}
    + (if $source == "" then {} else {source: $source} end)')

  if ! http::post_json "$GOOGLE_ENDPOINT" "$body" -H "X-goog-api-key: $key"; then
    http::transport_fail "Google Translate"
    return 1
  fi
  if ! http::ok; then
    google::fail
    return 1
  fi

  http::extract "Google Translate" '
    .data.translations[0] as $t
    | if ($t.translatedText? // null) == null then error("missing translation") else . end
    | {
        translation: $t.translatedText,
        detected: (($t.detectedSourceLanguage // (if $src == "auto" then "" else $src end))
                   | ascii_downcase | split("-")[0])
      }' --arg src "$src"
}
