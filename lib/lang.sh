#!/bin/bash
# Language code handling. Config and JSON use lowercase ISO 639-1 codes;
# each provider converts them to its own wire format. Sourced, never executed.

# lang::normalize CODE -> lowercase base code ("pt-BR" -> "pt"), "auto" kept.
# Prints nothing and fails for values that are not language codes.
lang::normalize() {
  local code=${1,,}
  code=${code//_/-}
  code=${code%%-*}
  if [[ $code == auto || $code =~ ^[a-z]{2,3}$ ]]; then
    printf '%s' "$code"
    return 0
  fi
  return 1
}
