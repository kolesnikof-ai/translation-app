#!/bin/bash
# Yandex Cloud Translate (v2) provider, translate only. It authenticates with
# an API key alone; no folder id is needed. Sourced, never executed.

PROVIDER_CAPS="translate"

YANDEX_ENDPOINT="${OMARCHY_TRANSLATE_YANDEX_ENDPOINT:-https://translate.api.cloud.yandex.net/translate/v2/translate}"

provider_translate() {
  local text=$1 src=$2 dst=$3 key body

  key=$(config::get '.keys.yandex // ""')
  if [[ -z $key ]]; then
    tr::error no_key "Yandex Translate API key is not set (keys.yandex in the config)"
    return 1
  fi

  body=$(jq -cn --arg text "$text" --arg target "$dst" --arg source "$([[ $src == auto ]] || printf '%s' "$src")" '
    {targetLanguageCode: $target, texts: [$text], format: "PLAIN_TEXT"}
    + (if $source == "" then {} else {sourceLanguageCode: $source} end)')

  if ! http::post_json "$YANDEX_ENDPOINT" "$body" -H "Authorization: Api-Key $key"; then
    http::transport_fail "Yandex Translate"
    return 1
  fi
  if ! http::ok; then
    http::fail "Yandex Translate"
    return 1
  fi

  http::extract "Yandex Translate" '
    .translations[0] as $t
    | if ($t.text? // null) == null then error("missing translation") else . end
    | {
        translation: $t.text,
        detected: (($t.detectedLanguageCode // (if $src == "auto" then "" else $src end))
                   | ascii_downcase | split("-")[0])
      }' --arg src "$src"
}
