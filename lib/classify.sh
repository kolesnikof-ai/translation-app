#!/bin/bash
# Word / phrase classification. Sourced, never executed.

# classify::kind TEXT -> "word" or "phrase".
#
# A word is a single token made of letters, optionally joined by "-" or "'"
# (so "well-known" and "don't" count). A run of CJK characters without
# spaces counts as a word up to 4 characters. Everything else is a phrase.
# jq is used because its regex engine knows Unicode properties regardless of
# the locale the command runs in.
classify::kind() {
  jq -rn --arg text "$1" '
    ($text | gsub("^\\s+|\\s+$"; "")) as $t
    | if ($t | test("[\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Hangul}]")) then
        if ($t | test("^[\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Hangul}]{1,4}$")) then "word" else "phrase" end
      elif ($t | test("^\\p{L}+([-\u0027\u2019]\\p{L}+)*$")) then "word"
      else "phrase" end'
}
