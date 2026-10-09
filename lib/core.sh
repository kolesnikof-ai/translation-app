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

# core::run TEXT FROM_OVERRIDE TO_OVERRIDE
# Prints the final result object (or an error object) and returns 0 on success.
core::run() {
  local text=$1 from=$2 to=$3 provider src dst explicit=0 translated

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

  translated=$(core::translate "$text" "$src" "$dst" "$explicit") || {
    printf '%s' "$translated"
    return 1
  }

  jq -cn --arg source "$text" --arg provider "$provider" --argjson translated "$translated" '
    {
      source: $source,
      detected: $translated.detected,
      target: $translated.target,
      kind: "phrase",
      translation: $translated.translation,
      provider: $provider,
      senses: []
    }'
}
