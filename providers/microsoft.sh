#!/bin/bash
# Microsoft Translator provider: translate plus Dictionary Lookup, which gives
# a word's translations grouped by part of speech. Sourced, never executed.

PROVIDER_CAPS="translate lookup"

MICROSOFT_ENDPOINT="${OMARCHY_TRANSLATE_MICROSOFT_ENDPOINT:-https://api.cognitive.microsofttranslator.com}"

microsoft::code() {
  case $1 in
    zh) printf 'zh-Hans' ;;
    *) printf '%s' "$1" ;;
  esac
}

# microsoft::headers -> prints one curl header argument per line.
microsoft::headers() {
  local key region
  key=$(config::get '.keys.microsoft // ""')
  region=$(config::get '.keys.microsoft_region // ""')
  printf '%s\n' "-H" "Ocp-Apim-Subscription-Key: $key"
  if [[ -n $region ]]; then
    printf '%s\n' "-H" "Ocp-Apim-Subscription-Region: $region"
  fi
}

# microsoft::fail -> error object for the last response. A 403 with an
# error code in the 4030xx range means the subscription quota is used up.
microsoft::fail() {
  local code
  code=$(jq -r '.error.code // empty' <<<"$HTTP_BODY" 2>/dev/null)
  if [[ $HTTP_STATUS == 403 && $code == 4030* ]]; then
    tr::error quota "Microsoft Translator quota exceeded: $(http::message)"
  else
    http::fail "Microsoft Translator"
  fi
}

microsoft::call() {
  local url=$1 body=$2 header
  local -a args=()
  while IFS= read -r header; do
    args+=("$header")
  done < <(microsoft::headers)

  if ! http::post_json "$url" "$body" "${args[@]}"; then
    http::transport_fail "Microsoft Translator"
    return 1
  fi
  if ! http::ok; then
    microsoft::fail
    return 1
  fi
}

provider_translate() {
  local text=$1 src=$2 dst=$3 url

  if [[ -z $(config::get '.keys.microsoft // ""') ]]; then
    tr::error no_key "Microsoft Translator key is not set (keys.microsoft in the config)"
    return 1
  fi

  url="$MICROSOFT_ENDPOINT/translate?api-version=3.0&textType=plain&to=$(microsoft::code "$dst")"
  [[ $src == auto ]] || url+="&from=$(microsoft::code "$src")"

  microsoft::call "$url" "$(jq -cn --arg text "$text" '[{Text: $text}]')" || return 1

  http::extract "Microsoft Translator" '
    .[0] as $r
    | if ($r.translations[0].text? // null) == null then error("missing translation") else . end
    | {
        translation: $r.translations[0].text,
        detected: (($r.detectedLanguage.language // (if $src == "auto" then "" else $src end))
                   | ascii_downcase | split("-")[0])
      }' --arg src "$src"
}

# provider_lookup WORD SRC DST -> senses grouped by part of speech, in the
# order the dictionary returns them (most frequent first). The dictionary needs
# an explicit source language, so "auto" yields no senses.
provider_lookup() {
  local word=$1 src=$2 dst=$3

  if [[ $src == auto || -z $src ]]; then
    printf '{"senses":[]}'
    return 0
  fi

  microsoft::call \
    "$MICROSOFT_ENDPOINT/dictionary/lookup?api-version=3.0&from=$(microsoft::code "$src")&to=$(microsoft::code "$dst")" \
    "$(jq -cn --arg text "$word" '[{Text: $text}]')" || return 1

  http::extract "Microsoft Translator" '
    def pos_name:
      {ADJ: "adjective", ADV: "adverb", CONJ: "conjunction", DET: "determiner",
       MODAL: "modal verb", NOUN: "noun", PREP: "preposition", PRON: "pronoun",
       VERB: "verb", OTHER: "other"}[(. // "OTHER") | ascii_upcase] // "other";
    def dedupe: reduce .[] as $v ([]; if index($v) == null then . + [$v] else . end);
    {
      senses: (
        reduce ((.[0].translations // [])[]) as $t ([];
          ($t.posTag | pos_name) as $pos
          | ($t.displayTarget // $t.normalizedTarget // "") as $variant
          | if $variant == "" then .
            elif any(.[]; .pos == $pos) then map(if .pos == $pos then .variants += [$variant] else . end)
            else . + [{pos: $pos, variants: [$variant]}] end)
        | map(.variants |= dedupe)
      )
    }'
}
