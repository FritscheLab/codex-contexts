#!/usr/bin/env bash

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
