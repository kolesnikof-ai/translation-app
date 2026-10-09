#!/bin/bash
# Provider selection. Sourced, never executed.
#
# A provider file defines:
#   PROVIDER_CAPS                 space separated: "translate" and optionally "lookup"
#   provider_translate TEXT SRC DST
#       success: prints {"translation": "...", "detected": "xx"} and returns 0
#       failure: prints an error object (see tr::error) and returns 1
#   provider_lookup WORD SRC DST  (only with the "lookup" capability)
#       prints {"senses": [{"pos": "noun", "variants": ["..."]}]} and returns 0
#
# Exactly one provider file is sourced per run, so a request never mixes data
# from several services.

TR_PROVIDERS="deepl microsoft google yandex libretranslate"

# provider::load NAME -> sources the provider; prints an error object on failure.
provider::load() {
  local name=$1 known
  for known in $TR_PROVIDERS; do
    if [[ $known == "$name" ]]; then
      # shellcheck source=/dev/null
      source "$TR_ROOT/providers/$name.sh"
      return 0
    fi
  done
  tr::error config "Unknown provider \"$name\". Use one of: $TR_PROVIDERS"
  return 1
}

# provider::has_capability CAP
provider::has_capability() {
  [[ " $PROVIDER_CAPS " == *" $1 "* ]]
}
