#!/bin/bash
# Translation pipeline. Sourced, never executed. Needs config.sh, lang.sh,
# provider.sh and common.sh.

# core::translate TEXT SRC DST EXPLICIT_DST
# Runs the translate call and, when the detected language equals the target,
# repeats it for fallback_target. EXPLICIT_DST=1 (the user picked the target)
# disables that fallback. Prints {"translation","detected","target"} or an
# error object.
core::translate() {
  local text=$1 src=$2 dst=$3 explicit=$4 response detected fallback

  response=$(provider_translate "$text" "$src" "$dst") || {
    printf '%s' "$response"
    return 1
  }
  detected=$(jq -r '.detected // ""' <<<"$response")
  fallback=$(lang::normalize "$(config::get '.fallback_target // ""')") || fallback=""

  if [[ $explicit != 1 && -n $detected && $detected == "$dst" && -n $fallback && $fallback != "$dst" ]]; then
    dst=$fallback
    response=$(provider_translate "$text" "$src" "$dst") || {
      printf '%s' "$response"
      return 1
    }
    detected=$(jq -r '.detected // ""' <<<"$response")
  fi

  jq -c --arg target "$dst" --arg detected "$detected" \
    '{translation: .translation, detected: $detected, target: $target}' <<<"$response"
}

# core::senses WORD SRC DST -> JSON array of {pos, variants}. A provider
# without the lookup capability, and any lookup failure, give an empty array:
# the translation itself is already complete.
core::senses() {
  local word=$1 src=$2 dst=$3 response
  provider::has_capability lookup || { echo '[]'; return 0; }
  [[ -n $src && $src != auto && $src != "$dst" ]] || { echo '[]'; return 0; }

  response=$(provider_lookup "$word" "$src" "$dst") || { echo '[]'; return 0; }
  jq -c '.senses // []' <<<"$response" 2>/dev/null || echo '[]'
}

# core::cap_variants JSON MAX -> the result with every sense limited to MAX
# variants. Applied on output so the cache keeps the full list.
core::cap_variants() {
  jq -c --argjson max "$2" '
    .senses |= (map(.variants |= .[:$max]) | map(select(.variants | length > 0)))' <<<"$1"
}

# core::cache_key PROVIDER SRC DST EXPLICIT TEXT -> cache key covering every
# setting that changes the answer: the language pair, whether the fallback
# target may apply (and which one), DeepL's formality and the LibreTranslate
# instance (another instance may translate differently).
core::cache_key() {
  local provider=$1 src=$2 dst=$3 explicit=$4 text=$5 extra instance
  extra="explicit=$explicit"
  [[ $explicit == 1 ]] || extra+=";fallback=$(config::get '.fallback_target // ""')"
  [[ $provider != deepl ]] || extra+=";formality=$(config::get '.deepl_formality // "default"')"
  if [[ $provider == libretranslate ]]; then
    instance=$(config::get '.libretranslate_url // ""')
    extra+=";instance=${instance%/}"
  fi
  cache::key "$provider" "$src" "$dst" "$extra" "$text"
}

# core::run TEXT FROM_OVERRIDE TO_OVERRIDE
# Prints the final result object (or an error object) and returns 0 on success.
core::run() {
  local text=$1 from=$2 to=$3 provider src dst explicit=0 translated kind senses detected max result key

  provider=$(config::get '.provider')
  provider::load "$provider" || return 1

  src=$(lang::normalize "${from:-$(config::get '.source')}") || {
    tr::error config "Invalid source language \"${from:-$(config::get '.source')}\""
    return 1
  }
  dst=$(lang::normalize "${to:-$(config::get '.target')}") || {
    tr::error config "Invalid target language \"${to:-$(config::get '.target')}\""
    return 1
  }
  [[ $dst != auto ]] || {
    tr::error config "Target language cannot be \"auto\""
    return 1
  }
  [[ -n $to ]] && explicit=1

  max=$(config::get '.ui.max_variants // 5')
  [[ $max =~ ^[0-9]+$ && $max -gt 0 ]] || max=5

  key=$(core::cache_key "$provider" "$src" "$dst" "$explicit" "$text")
  if result=$(cache::get "$key"); then
    cache::save_last "$result"
    core::cap_variants "$result" "$max"
    return 0
  fi

  translated=$(core::translate "$text" "$src" "$dst" "$explicit") || {
    printf '%s' "$translated"
    return 1
  }

  dst=$(jq -r '.target' <<<"$translated")
  detected=$(jq -r '.detected' <<<"$translated")
  kind=$(classify::kind "$text")
  senses='[]'
  [[ $kind == word ]] && senses=$(core::senses "$text" "$detected" "$dst")

  result=$(jq -cn --arg source "$text" --arg kind "$kind" --arg provider "$provider" \
    --argjson translated "$translated" --argjson senses "$senses" '
    {
      source: $source,
      detected: $translated.detected,
      target: $translated.target,
      kind: $kind,
      translation: $translated.translation,
      provider: $provider,
      senses: $senses
    }')

  cache::put "$key" "$result"
  cache::save_last "$result"
  core::cap_variants "$result" "$max"
}
