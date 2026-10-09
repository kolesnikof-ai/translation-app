#!/bin/bash
# Configuration loading. Sourced, never executed.

TR_CONFIG_DEFAULTS='{
  "target": "ru",
  "fallback_target": "en",
  "source": "auto",
  "provider": "deepl",
  "keys": {
    "deepl": "",
    "microsoft": "",
    "microsoft_region": "",
    "google": "",
    "yandex": "",
    "libretranslate": ""
  },
  "libretranslate_url": "",
  "deepl_formality": "default",
  "copy_fallback": false,
  "ui": {
    "position": "cursor",
    "width": 480,
    "height": 360,
    "show_language_switcher": false,
    "max_variants": 5
  }
}'

TR_CONFIG=""
TR_CONFIG_ERROR=""

config::path() {
  printf '%s' "${OMARCHY_TRANSLATE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/translate/config.json}"
}

# config::load -> fills TR_CONFIG with the user config merged over the defaults.
# Returns 1 and sets TR_CONFIG_ERROR (an error object) when the file is not
# valid JSON. Nothing is printed, so the caller keeps the assigned variables.
config::load() {
  local path user
  path=$(config::path)
  user='{}'
  if [[ -f $path ]]; then
    if ! user=$(jq -c 'if type == "object" then . else error("config must be a JSON object") end' "$path" 2>&1); then
      TR_CONFIG_ERROR=$(tr::error config "Invalid config at $path: $user")
      return 1
    fi
  fi

  TR_CONFIG=$(jq -cn --argjson defaults "$TR_CONFIG_DEFAULTS" --argjson user "$user" '$defaults * $user')
}

# config::get JQ_FILTER -> raw value from the merged config.
config::get() {
  jq -r "$1" <<<"$TR_CONFIG"
}
