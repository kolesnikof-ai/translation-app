#!/bin/bash
# HTTP helpers shared by the providers. Sourced, never executed.

HTTP_STATUS=""
HTTP_BODY=""
HTTP_ERROR=""

# http::post_json URL BODY [HEADER...]
# Each HEADER is a complete "Name: value" line, typically carrying an API key.
# The body goes through stdin and the headers through a private temporary file
# (curl -H @file), so neither the text nor the key shows up in the process list.
# Returns 0 when a response arrived (HTTP_STATUS / HTTP_BODY are set) and 1 on
# a transport failure (HTTP_ERROR is set).
http::post_json() {
  local url=$1 body=$2 out rc header dir headers_file=""
  local -a header_args=()
  shift 2

  HTTP_STATUS="" HTTP_BODY="" HTTP_ERROR=""

  if (($#)); then
    # A line break inside a value would smuggle in an extra header.
    for header in "$@"; do
      if [[ $header == *$'\n'* || $header == *$'\r'* ]]; then
        HTTP_ERROR="a request header contains a line break (check the API key in the config)"
        return 1
      fi
    done

    # mktemp creates the file with mode 0600. The per-user runtime dir is
    # preferred; it may be unset or missing outside a login session.
    for dir in "${XDG_RUNTIME_DIR:-}" "${TMPDIR:-/tmp}"; do
      [[ -n $dir && -d $dir && -w $dir ]] || continue
      headers_file=$(mktemp "$dir/omarchy-translate-headers.XXXXXX" 2>/dev/null) && break
      headers_file=""
    done
    if [[ -z $headers_file ]]; then
      HTTP_ERROR="cannot create a temporary file for the request headers"
      return 1
    fi
    printf '%s\n' "$@" >"$headers_file"
    header_args=(-H "@$headers_file")
  fi

  out=$(printf '%s' "$body" | curl --silent --show-error \
    --connect-timeout 8 --max-time "${OMARCHY_TRANSLATE_TIMEOUT:-20}" \
    -X POST -H 'Content-Type: application/json' "${header_args[@]}" \
    --data-binary @- --write-out $'\n%{http_code}' "$url" 2>&1)
  rc=$?
  [[ -z $headers_file ]] || rm -f "$headers_file"

  if ((rc != 0)); then
    HTTP_ERROR=${out//$'\n'/ }
    [[ -n $HTTP_ERROR ]] || HTTP_ERROR="curl failed with exit code $rc"
    return 1
  fi

  HTTP_STATUS=${out##*$'\n'}
  HTTP_BODY=${out%$'\n'*}
  return 0
}

# http::ok -> true for a 2xx status.
http::ok() {
  [[ $HTTP_STATUS == 2* ]]
}

# http::message -> best-effort human readable message from an error body.
http::message() {
  local message
  message=$(jq -r '
    (.message? // .error?.message? // .error? // .detail? // .Message? // .error_description? // empty)
    | if type == "string" then . else tostring end' <<<"$HTTP_BODY" 2>/dev/null | head -n 1)
  if [[ -z $message ]]; then
    message=$(head -c 200 <<<"$HTTP_BODY" | tr '\n' ' ')
  fi
  printf '%s' "$message"
}

# http::fail PROVIDER_LABEL -> prints the error object for the last response.
# 401/403 mean a missing or rejected key, 429/456 mean a quota or rate limit.
http::fail() {
  local label=$1 message
  message=$(http::message)
  case $HTTP_STATUS in
    401 | 403) tr::error no_key "$label rejected the API key${message:+: $message}" ;;
    429 | 456) tr::error quota "$label quota or rate limit exceeded${message:+: $message}" ;;
    *) tr::error network "$label returned HTTP $HTTP_STATUS${message:+: $message}" ;;
  esac
}

# http::transport_fail PROVIDER_LABEL -> error object for an unreachable service.
http::transport_fail() {
  tr::error network "Cannot reach $1: $HTTP_ERROR"
}

# http::extract LABEL JQ_FILTER [JQ_ARGS...] -> prints JQ_FILTER applied to the
# response body. An unparsable or unexpected body becomes an error object and
# a failure.
http::extract() {
  local label=$1 filter=$2 out
  shift 2
  if ! out=$(jq -ce "$@" "$filter" <<<"$HTTP_BODY" 2>/dev/null); then
    tr::error network "$label returned an unexpected response"
    return 1
  fi
  printf '%s' "$out"
}
