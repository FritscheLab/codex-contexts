#!/usr/bin/env bash

# Mock executables use these paths/status controls. Production launchers pass
# extra environment only by explicit name; fixtures opt in to their own controls.
export CODEX_CONTEXTS_ENV_ALLOW="CODEX_TEST_CODEX_ARGS CODEX_TEST_CODEX_ENV CODEX_TEST_CODEX_EXIT CODEX_TEST_CODEX_INPUT CODEX_TEST_CODE_ARGS CODEX_TEST_REVIEW_SNAPSHOT CODEX_TEST_CURL_ARGS CODEX_TEST_CURL_CONFIG CODEX_LAUNCH_TEST_ARGS CODEX_LAUNCH_TEST_DETAILS CODEX_LAUNCH_TEST_ENV CODEX_LAUNCH_TEST_EXIT CODEX_LAUNCH_TEST_NONCE CATALOG_TEST_ROOT CATALOG_TEST_HTTP_FAIL CATALOG_TEST_PARSE_FAIL"
export CODEX_CONTEXTS_ENV_ALLOW="$CODEX_CONTEXTS_ENV_ALLOW CODEX_DOCK_TEST_ARGS CODEX_DOCK_TEST_ENV"

resolve_codex_home_tool() {
  local bin_dir="$1" candidate
  local -a matches=()
  for candidate in "$bin_dir"/*home; do
    [[ -f "$candidate" && -x "$candidate" ]] && matches+=("$candidate")
  done
  if [[ "${#matches[@]}" -ne 1 ]]; then
    printf 'test setup failure: expected one executable *home tool in %s; found %s\n' \
      "$bin_dir" "${#matches[@]}" >&2
    return 1
  fi
  printf '%s\n' "${matches[0]}"
}
