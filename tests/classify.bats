#!/usr/bin/env bats

load test_helper

kind() {
  bash -c 'source "$1/lib/classify.sh"; classify::kind "$2"' _ "$REPO_ROOT" "$1"
}

@test "single letters-only token is a word" {
  [ "$(kind hello)" = word ]
  [ "$(kind a)" = word ]
  [ "$(kind Привет)" = word ]
  [ "$(kind Straße)" = word ]
}

@test "hyphen and apostrophe inside a word keep it a word" {
  [ "$(kind well-known)" = word ]
  [ "$(kind "don't")" = word ]
  [ "$(kind "don’t")" = word ]
  [ "$(kind "мама-мия")" = word ]
}

@test "leading or trailing hyphen makes it a phrase" {
  [ "$(kind -hello)" = phrase ]
  [ "$(kind "hello-")" = phrase ]
  [ "$(kind "'tis")" = phrase ]
}

@test "several tokens are a phrase" {
  [ "$(kind "hello world")" = phrase ]
  [ "$(kind "привет мир")" = phrase ]
  [ "$(kind $'line one\nline two')" = phrase ]
}

@test "digits, punctuation and underscores are a phrase" {
  [ "$(kind 123)" = phrase ]
  [ "$(kind hello.)" = phrase ]
  [ "$(kind foo_bar)" = phrase ]
  [ "$(kind abc123)" = phrase ]
}

@test "CJK without spaces is a word up to 4 characters" {
  [ "$(kind 你好)" = word ]
  [ "$(kind 日本語)" = word ]
  [ "$(kind 한국어)" = word ]
  [ "$(kind ひらがな)" = word ]
  [ "$(kind 你好世界)" = word ]
}

@test "CJK longer than 4 characters or mixed with other text is a phrase" {
  [ "$(kind 你好世界啊)" = phrase ]
  [ "$(kind "你 好")" = phrase ]
  [ "$(kind "hello 世界")" = phrase ]
}

@test "surrounding whitespace is ignored" {
  [ "$(kind "  hello  ")" = word ]
}
