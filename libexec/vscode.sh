#!/usr/bin/env bash
# Cross-platform VS Code discovery and validated identity launches.
# Loaded by bin/codex-home; no commands run at import.

resolve_vscode_cli() {
  local configured="${CODEX_VSCODE_CLI:-}"
  local candidate

  if [[ -n "$configured" ]]; then
    if [[ "$configured" == */* ]]; then
      [[ -x "$configured" ]] || die "CODEX_VSCODE_CLI is not executable: $configured"
      printf '%s\n' "$configured"
      return 0
    fi
    command -v "$configured" >/dev/null 2>&1 ||
      die "CODEX_VSCODE_CLI command was not found: $configured"
    command -v "$configured"
    return 0
  fi

  if command -v code >/dev/null 2>&1; then
    command -v code
    return 0
  fi

  for candidate in \
    "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
    "$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
    "/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code"
  do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  die "VS Code CLI was not found; install the 'code' shell command or set CODEX_VSCODE_CLI"
}

# Only standard VS Code bundles qualify for a named editor copy.
launch_vscode_from_dock() {
  [[ "$(uname -s)" == Darwin && $# -ge 2 && $# -le 3 ]] || die "invalid Dock launcher invocation"
  local name="$1" state="$2" project
  # Saved-project launches use the same validation and CLI as folder launches.
  if [[ $# -eq 3 ]]; then project="$3"; else project="$(cat "$state")"; fi
  launch_vscode "$name" "$project"
}

launch_vscode_project_env() {
  local project_dir="$1" expected_name="$2"
  local project_abs helper vscode_cli extensions_dir homes_root
  command -v direnv >/dev/null 2>&1 || die "direnv is not installed"
  direnv version 2.32.2 >/dev/null ||
    die "direnv 2.32.2 or newer is required for project path escaping; upgrade direnv"
  [[ -d "$project_dir" ]] || die "project directory does not exist: $project_dir"
  project_abs="$(cd "$project_dir" && pwd -P)"
  validate_single_line "project path" "$project_abs"
  # direnv treats an unreadable .envrc as absent. Read it explicitly so a
  # privacy denial is reported before selecting an identity.
  if ! cat "$project_abs/.envrc" >/dev/null; then
    die "cannot read $project_abs/.envrc; check the file and Codex Project's folder access in macOS Privacy & Security"
  fi

  helper="$CODEX_CONTEXTS_LAUNCHER"
  vscode_cli="$(resolve_vscode_cli)"
  extensions_dir="${CODEX_VSCODE_EXTENSIONS_DIR:-$HOME/.vscode/extensions}"
  homes_root="$CODEX_HOMES_ROOT"
  [[ "$homes_root" == /* ]] || homes_root="$PWD/$homes_root"
  # Pin launcher settings and the identity registry from the caller. Load the
  # project's environment once, then validate and execute within that process.
  project_direnv_exec "$project_abs" /usr/bin/env \
    -u BASH_ENV -u ENV -u PYTHONPATH -u PYTHONHOME -u NODE_OPTIONS -u NODE_PATH \
    -u LD_PRELOAD -u LD_LIBRARY_PATH -u DYLD_INSERT_LIBRARIES -u DYLD_LIBRARY_PATH \
    CODEX_HOMES_ROOT="$homes_root" "$BASH" "$helper" _vscode-loaded "$project_abs" "$expected_name" \
    "$HOME/.codex" "$vscode_cli" "$extensions_dir" "${CODEX_VSCODE_DOCK_LABEL:-0}"
}

launch_vscode_loaded() {
  [[ $# -eq 6 ]] || die "invalid internal VS Code launch invocation"
  local project_abs="$1" expected_name="$2" default_home="$3"
  local vscode_cli="$4" extensions_dir="$5" dock_label="$6"
  local name workspace home vscode_data macos_executable dock_app="" running_pid running_command
  local -a code_args
  cd "$project_abs"
  home="$(project_launch_home "$project_abs" "$default_home")"
  name="$CODEX_IDENTITY"
  data_helper identity "$home" || return
  data_helper launch-check "$home" --cd "$project_abs" || return
  validate_umgpt_identity_config "$name" || return
  validate_project_umgpt_model "$name" "$project_abs" || return
  [[ -z "$expected_name" || "$name" == "$expected_name" ]] ||
    die "project selects '$name', not '$expected_name'; open it with the selected identity or review its .envrc"
  workspace="$(managed_project_workspace "$project_abs")"
  [[ -f "$workspace" ]] || die "missing $workspace; run: codex-home project $name '$project_abs'"

  vscode_data="$home/vscode-user-data"
  mkdir -p "$vscode_data"
  code_args=(
    --new-window
    --user-data-dir "$vscode_data"
  )

  if [[ -d "$extensions_dir" ]]; then
    code_args+=(--extensions-dir "$extensions_dir")
  fi
  code_args+=("$workspace")

  printf 'Launching isolated VS Code as %s.\n' "$(identity_label "$name")"
  if [[ "$(identity_umgpt_scope "$name" 2>/dev/null || true)" == "low-sensitivity" ]]; then
    printf '%s\n' '  LOW-SENSITIVITY DATA ONLY: verify the selected model before use.'
  fi
  printf '  User data: %s\n' "$vscode_data"
  if [[ -d "$extensions_dir" ]]; then
    printf '  Extensions: %s\n' "$extensions_dir"
  else
    printf '  Extensions: isolated (install openai.chatgpt in this window)\n'
  fi
  printf 'Start a new Codex chat after the window opens.\n'
  if [[ "$(uname -s)" == Darwin ]]; then
    if [[ "$dock_label" != 0 ]] && macos_executable="$(macos_vscode_executable "$vscode_cli")"; then
      dock_app="$(prepare_macos_vscode_editor "$name" "$home" "$macos_executable")"
      printf '  Named editor: %s\n' "$dock_app"
      vscode_cli="$dock_app/Contents/Resources/app/bin/code"
      if [[ ! -x "$vscode_cli" ]]; then
        vscode_cli="$dock_app/Contents/Resources/app/bin/code-insiders"
      fi
      if macos_vscode_is_running "$vscode_data"; then
        running_pid="$(cat "$vscode_data/code.lock")"
        running_command="$(/bin/ps -p "$running_pid" -o comm= 2>/dev/null || true)"
        if [[ "$running_command" == "$macos_executable" && "$running_command" != "$dock_app/Contents/MacOS/"* ]]; then
          printf 'The current editor still uses its previous Dock name. Quit this identity\047s VS Code instance and reopen through Codex Project to use VS Code - %s.\n' "$name" >&2
        fi
      fi
    fi
  fi
  local launch_status=0
  if identity_command "$name" "$home" "$vscode_cli" "${code_args[@]}"; then
    :
  else
    launch_status=$?
  fi
  macos_vscode_unregister_editor "$dock_app"
  return "$launch_status"
}

register_vscode_open_with() {
  [[ $# -eq 1 ]] || die "usage: codex-home vscode-open-with NAME"
  [[ "$(uname -s)" == Darwin ]] || die "VS Code Finder entries are only available on macOS"
  local name="$1" home
  ensure_identity "$name"
  home="$(identity_home "$name")"
  ensure_macos_vscode_open_with "$name" "$home"
  printf 'Finder Open With entry: %s\n' "$(macos_vscode_open_with_path "$name")"
}

launch_vscode() {
  [[ $# -ge 1 && $# -le 2 ]] || die "usage: codex-home vscode NAME [PROJECT_DIR]"
  ensure_identity "$1"
  launch_vscode_project_env "${2:-.}" "$1"
}

launch_vscode_project() {
  [[ $# -le 1 ]] || die "usage: codex-home vscode-project [PROJECT_DIR]"
  launch_vscode_project_env "${1:-.}" ""
}

