#!/bin/bash
# DeepL provider (translate only). Sourced, never executed.
# The DeepL API does not return dictionary data, so words get no senses.

PROVIDER_CAPS="translate"

# DeepL expects uppercase codes and regional variants for some targets.
deepl::target_code() {
  case $1 in
    en) printf 'EN-US' ;;
    pt) printf 'PT-BR' ;;
    *) printf '%s' "${1^^}" ;;
  esac
}

deepl::source_code() {
  printf '%s' "${1^^}"
}

# Free keys end in ":fx" and use a different host.
deepl::endpoint() {
  if [[ $1 == *:fx ]]; then
    printf 'https://api-free.deepl.com'
  else
    printf 'https://api.deepl.com'
  fi
}

# The "prefer_*" variants fall back silently for languages without formality
# support, where plain "more"/"less" would make the API reject the request.
deepl::formality() {
  case $(config::get '.deepl_formality // "default"') in
    more | prefer_more) printf 'prefer_more' ;;
    less | prefer_less) printf 'prefer_less' ;;
  esac
}

provider_translate() {
  local text=$1 src=$2 dst=$3 key body formality

  key=$(config::get '.keys.deepl // ""')
  if [[ -z $key ]]; then
    tr::error no_key "DeepL API key is not set (keys.deepl in the config)"
    return 1
  fi

  formality=$(deepl::formality)
  body=$(jq -cn \
    --arg text "$text" \
    --arg target "$(deepl::target_code "$dst")" \
    --arg source "$([[ $src == auto ]] || deepl::source_code "$src")" \
    --arg formality "$formality" '
    {text: [$text], target_lang: $target}
    + (if $source == "" then {} else {source_lang: $source} end)
    + (if $formality == "" then {} else {formality: $formality} end)')

  if ! http::post_json "$(deepl::endpoint "$key")/v2/translate" "$body" \
    "Authorization: DeepL-Auth-Key $key"; then
    http::transport_fail "DeepL"
    return 1
  fi
  if ! http::ok; then
    http::fail "DeepL"
    return 1
  fi

  http::extract "DeepL" '
    .translations[0] as $t
    | if ($t.text? // null) == null then error("missing translation") else . end
    | {translation: $t.text, detected: (($t.detected_source_language // "") | ascii_downcase)}'
}
