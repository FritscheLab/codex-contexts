#!/usr/bin/env bash
# Project templates, ownership, Git exclusions, review, and direnv approval.
# Loaded by bin/codex-home; no commands run at import.

status_bar_color() {
  local name="$1"
  local kind="$2"
  case "$kind" in
    codex-default) printf '%s\n' "#57606A" ;;
    chatgpt-subscription)
      if [[ "$name" == "pro" ]]; then
        printf '%s\n' "#0969DA"
      elif [[ "$name" == "business" ]]; then
        printf '%s\n' "#6F42C1"
      else
        printf '%s\n' "#1F883D"
      fi
      ;;
    api-key) printf '%s\n' "#B35C00" ;;
    umgpt-openai) printf '%s\n' "#00274C" ;;
    umgpt-low) printf '%s\n' "#B31B1B" ;;
    *) printf '%s\n' "#57606A" ;;
  esac
}

gitignore_escape_literal() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\*/\\*}"
  value="${value//\?/\\?}"
  value="${value//\[/\\[}"
  printf '%s' "$value"
}

project_workspace_git_path() {
  local project_abs="$1"
  local project_name
  [[ "$project_abs" != "/" ]] || die "the filesystem root cannot be used as a project"
  project_name="$(basename "$project_abs")"
  printf '.vscode/%s.code-workspace\n' "$project_name"
}

project_workspace_path() {
  local project_abs="$1"
  printf '%s/%s\n' "$project_abs" "$(project_workspace_git_path "$project_abs")"
}

legacy_project_workspace_path() {
  local project_abs="$1"
  printf '%s/.vscode/codex-context.code-workspace\n' "$project_abs"
}

ensure_project_files_untracked() {
  local project_abs="$1"
  local workspace="$2"
  local workspace_rel
  if ! git -C "$project_abs" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi
  workspace_rel="${workspace#"$project_abs/"}"
  [[ "$workspace_rel" != "$workspace" ]] ||
    die "VS Code workspace is outside the project: $workspace"
  if git -C "$project_abs" ls-files --error-unmatch -- .envrc >/dev/null 2>&1; then
    die "refusing to manage .envrc because that path is already tracked by Git"
  fi
  if git -C "$project_abs" ls-files --error-unmatch -- "$workspace_rel" \
    >/dev/null 2>&1; then
    die "refusing to manage $workspace_rel because that path is already tracked by Git"
  fi
}

project_git_exclude_details() {
  local project_abs="$1"
  local project_prefix exclude_file escaped_prefix workspace_rel
  local escaped_workspace escaped_legacy_workspace

  project_prefix="$(git -C "$project_abs" rev-parse --show-prefix)" ||
    die "could not determine the Git path for $project_abs"
  exclude_file="$(cd "$project_abs" && git rev-parse --git-path info/exclude)" ||
    die "could not locate the repository's local Git exclude file"
  if [[ "$exclude_file" != /* ]]; then
    exclude_file="$project_abs/$exclude_file"
  fi

  escaped_prefix="$(gitignore_escape_literal "$project_prefix")"
  workspace_rel="$(project_workspace_git_path "$project_abs")"
  escaped_workspace="$(gitignore_escape_literal "${project_prefix}${workspace_rel}")"
  escaped_legacy_workspace="$(
    gitignore_escape_literal "${project_prefix}.vscode/codex-context.code-workspace"
  )"
  printf '%s\n' "$exclude_file"
  printf '/%s.envrc\n' "$escaped_prefix"
  printf '/%s\n' "$escaped_workspace"
  printf '/%s\n' "$escaped_legacy_workspace"
}

add_project_git_excludes() {
  local project_abs="$1"
  local details exclude_file envrc_pattern workspace_pattern

  if ! git -C "$project_abs" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi

  ensure_project_files_untracked "$project_abs" "$(project_workspace_path "$project_abs")"
  details="$(project_git_exclude_details "$project_abs")" || return
  {
    IFS= read -r exclude_file
    IFS= read -r envrc_pattern
    IFS= read -r workspace_pattern
  } <<< "$details"

  if grep -Fqx -- "$envrc_pattern" "$exclude_file" 2>/dev/null &&
    grep -Fqx -- "$workspace_pattern" "$exclude_file" 2>/dev/null; then
    printf '%s\n' "$exclude_file"
    return 0
  fi

  mkdir -p "$(dirname "$exclude_file")" || return
  if [[ -s "$exclude_file" ]]; then
    printf '\n' >> "$exclude_file" || return
  fi
  printf '%s\n' '# Added by codex-home; machine-local project configuration.' >> "$exclude_file" || return
  if ! grep -Fqx -- "$envrc_pattern" "$exclude_file" 2>/dev/null; then
    printf '%s\n' "$envrc_pattern" >> "$exclude_file" || return
  fi
  if ! grep -Fqx -- "$workspace_pattern" "$exclude_file" 2>/dev/null; then
    printf '%s\n' "$workspace_pattern" >> "$exclude_file" || return
  fi
  printf '%s\n' "$exclude_file"
}

remove_project_git_excludes() {
  local project_abs="$1"
  local scope="${2:-all}"
  local details exclude_file envrc_pattern workspace_pattern
  local legacy_workspace_pattern exclude_tmp

  if ! git -C "$project_abs" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi

  details="$(project_git_exclude_details "$project_abs")" || return
  {
    IFS= read -r exclude_file
    IFS= read -r envrc_pattern
    IFS= read -r workspace_pattern
    IFS= read -r legacy_workspace_pattern
  } <<< "$details"
  [[ -f "$exclude_file" ]] || return 0
  if [[ "$scope" == legacy ]]; then
    [[ "$legacy_workspace_pattern" != "$workspace_pattern" ]] || return 0
  fi

  exclude_tmp="$(mktemp "${exclude_file}.codex-home.XXXXXX")" || return
  if ! CODEX_EXCLUDE_SCOPE="$scope" CODEX_ENVRC_PATTERN="$envrc_pattern" \
    CODEX_WORKSPACE_PATTERN="$workspace_pattern" \
    CODEX_LEGACY_WORKSPACE_PATTERN="$legacy_workspace_pattern" \
    awk '
      $0 == ENVIRON["CODEX_LEGACY_WORKSPACE_PATTERN"] { next }
      ENVIRON["CODEX_EXCLUDE_SCOPE"] != "legacy" &&
        ($0 == ENVIRON["CODEX_ENVRC_PATTERN"] ||
         $0 == ENVIRON["CODEX_WORKSPACE_PATTERN"]) { next }
      { print }
    ' "$exclude_file" > "$exclude_tmp"; then
    rm -f "$exclude_tmp"
    die "could not update $exclude_file"
  fi
  if ! mv "$exclude_tmp" "$exclude_file"; then
    rm -f "$exclude_tmp"
    die "could not update $exclude_file"
  fi
  if [[ "$scope" != legacy ]]; then
    printf '%s\n' "$exclude_file"
  fi
}

render_project_envrc() {
  local name="$1"
  local helper_dir="${2:-$SCRIPT_DIR}"
  local home label home_quoted helper_quoted
  home="$(identity_home "$name")" || return
  label="$(identity_label "$name")" || return
  validate_single_line "identity home" "$home"
  validate_single_line "helper path" "$helper_dir"
  home_quoted="$(shell_double_quote "$home")" || return
  helper_quoted="$(shell_double_quote "$helper_dir")" || return
  cat <<EOF
$PROJECT_ENVRC_MARKER
export CODEX_IDENTITY="$name"
export CODEX_HOME=$home_quoted

if [[ ! -d "\$CODEX_HOME" ]]; then
  log_error "Missing Codex identity directory: \$CODEX_HOME"
  return 1
fi

EOF
  if [[ "${3:-0}" == 1 ]]; then
    printf '%s\n' 'dotenv_if_exists "$CODEX_HOME/.env"'
  fi
  cat <<EOF
PATH_add $helper_quoted
watch_file "\$CODEX_HOME/config.toml"
EOF
  if [[ "${4:-0}" != 1 ]]; then
    cat <<'EOF'
if [[ -f "$CODEX_HOME/api-key.env" ]]; then
  watch_file "$CODEX_HOME/api-key.env"
fi
EOF
  fi
  cat <<EOF
if [[ -f "\$CODEX_HOME/.env" ]]; then
  watch_file "\$CODEX_HOME/.env"
fi
log_status "Codex identity: $label | CODEX_HOME=\$CODEX_HOME"
EOF
}

render_project_workspace() {
  local name="$1"
  local project_name="$2"
  local kind color identity_short folder_name_json window_title window_title_json
  kind="$(identity_kind "$name")" || return
  color="$(status_bar_color "$name" "$kind")" || return
  identity_short="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')" || return
  folder_name_json="$(jq -Rn --arg value "$project_name" '$value')" || return
  window_title="$project_name [CODEX: $identity_short]"
  window_title_json="$(jq -Rn --arg value "$window_title" '$value')" || return
  printf '%s\n' "$PROJECT_WORKSPACE_MARKER" || return
  cat <<EOF
{
  "folders": [
    { "name": $folder_name_json, "path": ".." }
  ],
  "settings": {
    "window.title": $window_title_json,
    "workbench.colorCustomizations": {
      "statusBar.background": "$color",
      "statusBar.foreground": "#FFFFFF",
      "statusBar.noFolderBackground": "$color",
      "statusBar.debuggingBackground": "$color"
    }
  }
}
EOF
}

render_legacy_project_workspace() {
  local name="$1"
  local include_marker="${2:-1}"
  local kind label color
  kind="$(identity_kind "$name")" || return
  label="$(identity_label "$name")" || return
  color="$(status_bar_color "$name" "$kind")" || return
  if [[ "$include_marker" == "1" ]]; then
    printf '%s\n' "$PROJECT_WORKSPACE_MARKER" || return
  fi
  cat <<EOF
{
  "folders": [
    { "path": ".." }
  ],
  "settings": {
    "window.title": "[CODEX: $label] \${dirty}\${activeEditorShort}\${separator}\${rootName}\${separator}\${appName}",
    "workbench.colorCustomizations": {
      "statusBar.background": "$color",
      "statusBar.foreground": "#FFFFFF",
      "statusBar.noFolderBackground": "$color",
      "statusBar.debuggingBackground": "$color"
    }
  }
}
EOF
}

write_project_templates() (
  local name="$1"
  local project_abs="$2"
  local envrc="$project_abs/.envrc"
  local project_name workspace
  local envrc_tmp="" workspace_tmp="" backup_dir="" restore=0

  cleanup_project_templates() {
    local status=$? keep_backups=0 target backup
    trap - EXIT HUP INT TERM
    if [[ "$restore" == 1 ]]; then
      for target in "$envrc" "$workspace"; do
        if [[ "$target" == "$envrc" ]]; then
          backup="$backup_dir/envrc"
        else
          backup="$backup_dir/workspace"
        fi
        if [[ -f "$backup" ]]; then
          mv -f "$backup" "$target" || keep_backups=1
        else
          rm -f "$target" || keep_backups=1
        fi
      done
    fi
    [[ -z "$envrc_tmp" ]] || rm -f "$envrc_tmp"
    [[ -z "$workspace_tmp" ]] || rm -f "$workspace_tmp"
    if [[ -n "$backup_dir" ]]; then
      if [[ "$keep_backups" == 1 ]]; then
        printf 'codex-home: restoration failed; recover original files from %s before reopening this project\n' "$backup_dir" >&2
        status=1
      else
        rm -f "$backup_dir/envrc" "$backup_dir/workspace"
        rmdir "$backup_dir"
      fi
    fi
    exit "$status"
  }

  project_name="$(basename "$project_abs")" || return
  workspace="$(project_workspace_path "$project_abs")" || return
  umask 077
  trap cleanup_project_templates EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  mkdir -p "$project_abs/.vscode" || die "could not create the project workspace directory"
  envrc_tmp="$(mktemp "$project_abs/.envrc.codex-home.XXXXXX")" || die "could not stage .envrc"
  workspace_tmp="$(mktemp "${workspace}.codex-home.XXXXXX")" || die "could not stage the workspace"
  if ! render_project_envrc "$name" > "$envrc_tmp" ||
    ! render_project_workspace "$name" "$project_name" > "$workspace_tmp"; then
    die "could not render project configuration"
  fi
  backup_dir="$(mktemp -d "$project_abs/.codex-home-backup.XXXXXX")" || die "could not prepare project backups"
  if [[ -f "$envrc" ]]; then
    cp -p "$envrc" "$backup_dir/envrc" || die "could not back up $envrc"
  fi
  if [[ -f "$workspace" ]]; then
    cp -p "$workspace" "$backup_dir/workspace" || die "could not back up $workspace"
  fi
  restore=1
  mv "$envrc_tmp" "$envrc" || die "could not replace $envrc"
  mv "$workspace_tmp" "$workspace" || die "could not replace $workspace"
  restore=0
)

generated_project_identity() {
  local envrc="$1"
  local name helper_dir="" helper_quoted remaining character expected key_export legacy_watch

  [[ -f "$envrc" && ! -L "$envrc" ]] || return 1
  [[ "$(sed -n '1p' "$envrc")" == "$PROJECT_ENVRC_MARKER" ]] || return 1
  name="$(sed -n 's/^export CODEX_IDENTITY="\([a-zA-Z0-9][a-zA-Z0-9_-]*\)"$/\1/p' "$envrc")"
  [[ -n "$name" && "$(grep -Ec '^export CODEX_IDENTITY=' "$envrc")" -eq 1 ]] || return 1
  helper_quoted="$(sed -n 's/^PATH_add //p' "$envrc")" || return 1
  [[ "$helper_quoted" == \"*\" && "$(grep -Ec '^PATH_add ' "$envrc")" -eq 1 ]] || return 1
  remaining="${helper_quoted:1:${#helper_quoted}-2}"
  # Decode only shell_double_quote's literal format; never evaluate project code.
  while [[ -n "$remaining" ]]; do
    character="${remaining:0:1}"
    remaining="${remaining:1}"
    case "$character" in
      \\)
        character="${remaining:0:1}"
        remaining="${remaining:1}"
        case "$character" in \\|\"|\$|\`) ;; *) return 1 ;; esac
        ;;
      \"|\$|\`) return 1 ;;
    esac
    helper_dir+="$character"
  done
  [[ "$helper_dir" == /* ]] || return 1
  # Recognize earlier templates for review/migration without evaluating them.
  for key_export in 0 1; do
    for legacy_watch in 0 1; do
      expected="$(render_project_envrc "$name" "$helper_dir" "$key_export" "$legacy_watch")" || return 1
      if cmp -s "$envrc" <(printf '%s\n' "$expected"); then
        printf '%s\n' "$name"
        return 0
      fi
    done
  done
  return 1
}

workspace_matches_generated_template() {
  local workspace="$1"
  local name="$2"
  local project_abs="$3"
  local project_name expected

  [[ -f "$workspace" && ! -L "$workspace" ]] || return 1
  project_name="$(basename "$project_abs")"
  expected="$(render_project_workspace "$name" "$project_name")" || return 1
  if cmp -s "$workspace" <(printf '%s\n' "$expected"); then return 0; fi
  expected="$(render_legacy_project_workspace "$name")" || return 1
  cmp -s "$workspace" <(printf '%s\n' "$expected") ||
    cmp -s "$workspace" <(printf '%s\n' "${expected#*$'\n'}")
}

managed_project_workspace() {
  local project_abs="$1"
  local workspace legacy_workspace
  workspace="$(project_workspace_path "$project_abs")"
  legacy_workspace="$(legacy_project_workspace_path "$project_abs")"

  if [[ "$workspace" != "$legacy_workspace" &&
    ( -e "$workspace" || -L "$workspace" ) &&
    ( -e "$legacy_workspace" || -L "$legacy_workspace" ) ]]; then
    die "refusing to choose between both $workspace and $legacy_workspace"
  fi
  if [[ -e "$workspace" || -L "$workspace" ]]; then
    printf '%s\n' "$workspace"
  elif [[ -e "$legacy_workspace" || -L "$legacy_workspace" ]]; then
    printf '%s\n' "$legacy_workspace"
  else
    printf '%s\n' "$workspace"
  fi
}

managed_project_identity() {
  local project_abs="$1"
  local workspace="$2"
  local envrc="$project_abs/.envrc"
  local name

  [[ ! -L "$project_abs/.vscode" ]] ||
    die "refusing to manage a project whose .vscode directory is a symbolic link"
  name="$(generated_project_identity "$envrc")" ||
    die "refusing to replace $envrc because it does not exactly match a generated codex-home file"
  workspace_matches_generated_template "$workspace" "$name" "$project_abs" ||
    die "refusing to replace $workspace because it does not exactly match a generated codex-home file"
  ensure_project_files_untracked "$project_abs" "$workspace"
  printf '%s\n' "$name"
}

write_project_files() {
  [[ $# -ge 1 && $# -le 2 ]] || die "usage: codex-home project NAME [PROJECT_DIR]"
  local name="$1"
  local project_dir="${2:-.}"
  local project_abs envrc workspace legacy_workspace git_exclude
  ensure_identity "$name"
  [[ -d "$project_dir" ]] || die "project directory does not exist: $project_dir"
  project_abs="$(cd "$project_dir" && pwd -P)"
  validate_single_line "project path" "$project_abs"
  envrc="$project_abs/.envrc"
  workspace="$(project_workspace_path "$project_abs")"
  legacy_workspace="$(legacy_project_workspace_path "$project_abs")"

  [[ ! -e "$envrc" && ! -L "$envrc" ]] ||
    die "refusing to overwrite existing $envrc (see docs/projects-vscode.md for the block to add manually)"
  [[ ! -e "$workspace" && ! -L "$workspace" ]] ||
    die "refusing to overwrite existing $workspace"
  if [[ "$legacy_workspace" != "$workspace" ]]; then
    [[ ! -e "$legacy_workspace" && ! -L "$legacy_workspace" ]] ||
      die "refusing to replace existing workspace $legacy_workspace"
  fi
  if [[ -e "$project_abs/.vscode" ]]; then
    [[ -d "$project_abs/.vscode" && ! -L "$project_abs/.vscode" ]] ||
      die "refusing to use $project_abs/.vscode because it is not a regular directory"
  fi

  git_exclude="$(add_project_git_excludes "$project_abs")" || return
  write_project_templates "$name" "$project_abs" || return

  printf 'Configured %s for %s\n' "$project_abs" "$(identity_label "$name")"
  printf '  direnv:   %s\n' "$envrc"
  printf '  VS Code:  %s\n' "$workspace"
  if [[ -n "$git_exclude" ]]; then
    printf '  Git:      locally excluded by %s\n' "$git_exclude"
  else
    printf '  Git:      not inside a Git work tree; no exclusion was needed\n'
  fi
  printf 'Next:\n'
  printf '  direnv allow %q\n' "$project_abs"
  printf '  %q vscode %q %q\n' "$0" "$name" "$project_abs"
}

revoke_project_approval() {
  local project_abs="$1"
  local deny_error

  if deny_error="$(direnv deny "$project_abs" 2>&1)"; then
    return 0
  fi
  # A missing approval file means there is no approval left to revoke.
  case "$deny_error" in
    "direnv: error remove "*/direnv/allow/*": no such file or directory")
      return 0
      ;;
  esac
  printf '%s\n' "$deny_error" >&2
  die "could not revoke direnv approval for $project_abs"
}

change_project_files() {
  [[ $# -ge 1 && $# -le 2 ]] ||
    die "usage: codex-home project-change NAME [PROJECT_DIR]"
  local name="$1"
  local project_dir="${2:-.}"
  local project_abs previous_name workspace new_workspace git_exclude
  ensure_identity "$name"
  command -v direnv >/dev/null 2>&1 || die "direnv is not installed"
  [[ -d "$project_dir" ]] || die "project directory does not exist: $project_dir"
  project_abs="$(cd "$project_dir" && pwd -P)"
  validate_single_line "project path" "$project_abs"
  workspace="$(managed_project_workspace "$project_abs")"
  previous_name="$(managed_project_identity "$project_abs" "$workspace")"
  new_workspace="$(project_workspace_path "$project_abs")"
  if [[ "$workspace" != "$new_workspace" ]]; then
    [[ ! -e "$new_workspace" && ! -L "$new_workspace" ]] ||
      die "refusing to overwrite existing $new_workspace"
  fi

  revoke_project_approval "$project_abs"
  git_exclude="$(add_project_git_excludes "$project_abs")" || return
  write_project_templates "$name" "$project_abs" || return
  if [[ "$workspace" != "$new_workspace" ]]; then
    rm -f "$workspace" || return
    remove_project_git_excludes "$project_abs" legacy || return
  fi

  printf 'Changed %s from %s to %s.\n' "$project_abs" "$previous_name" "$(identity_label "$name")"
  printf '  direnv:   %s/.envrc (approval revoked; review before allowing)\n' "$project_abs"
  printf '  VS Code:  %s\n' "$new_workspace"
  if [[ -n "$git_exclude" ]]; then
    printf '  Git:      locally excluded by %s\n' "$git_exclude"
  fi
  printf 'Next:\n'
  printf '  direnv allow %q\n' "$project_abs"
  printf '  %q vscode %q %q\n' "$0" "$name" "$project_abs"
}

reset_project_files() {
  [[ $# -le 1 ]] || die "usage: codex-home project-reset [PROJECT_DIR]"
  local project_dir="${1:-.}"
  local project_abs previous_name workspace git_exclude
  command -v direnv >/dev/null 2>&1 || die "direnv is not installed"
  [[ -d "$project_dir" ]] || die "project directory does not exist: $project_dir"
  project_abs="$(cd "$project_dir" && pwd -P)"
  validate_single_line "project path" "$project_abs"
  workspace="$(managed_project_workspace "$project_abs")"
  previous_name="$(managed_project_identity "$project_abs" "$workspace")"

  revoke_project_approval "$project_abs"
  rm -f "$project_abs/.envrc" "$workspace"
  rmdir "$project_abs/.vscode" >/dev/null 2>&1 || true
  git_exclude="$(remove_project_git_excludes "$project_abs")" || return

  printf 'Removed generated Codex project context for %s (was %s).\n' \
    "$project_abs" "$previous_name"
  if [[ -n "$git_exclude" ]]; then
    printf '  Git:      removed this project\047s patterns from %s\n' "$git_exclude"
  fi
  printf 'Identity homes, credentials, .codex, and unrelated VS Code settings were not changed.\n'
}

review_project_envrc() {
  [[ $# -le 1 ]] || die "usage: codex-home project-review [PROJECT_DIR]"
  local project_dir="${1:-.}"
  local project_abs envrc workspace name vscode_cli review_dir review_dir_q
  local review_file baseline

  [[ -d "$project_dir" ]] || die "project directory does not exist: $project_dir"
  project_abs="$(cd "$project_dir" && pwd -P)"
  validate_single_line "project path" "$project_abs"
  envrc="$project_abs/.envrc"
  workspace="$(managed_project_workspace "$project_abs")"
  name="$(managed_project_identity "$project_abs" "$workspace")"
  vscode_cli="$(resolve_vscode_cli)"

  review_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-envrc-review.XXXXXX")"
  printf -v review_dir_q '%q' "$review_dir"
  trap "chmod 700 $review_dir_q 2>/dev/null || true; rm -rf -- $review_dir_q" EXIT HUP INT TERM
  review_file="$review_dir/$(basename "$project_abs").envrc-review.sh"
  baseline="$review_dir/.envrc-baseline"
  cp "$envrc" "$review_file"
  cp "$envrc" "$baseline"
  chmod 400 "$review_file" "$baseline"
  chmod 500 "$review_dir"

  printf 'Opening a read-only review snapshot for %s.\n' "$(identity_label "$name")"
  printf 'Close the VS Code review window to return to the approval prompt.\n'
  data_helper review "$name" "$(identity_home "$name")" \
    "$vscode_cli" --new-window --wait --disable-extensions "$review_file"

  cmp -s "$baseline" "$envrc" ||
    die "$envrc changed while it was being reviewed; review it again before approval"
  cmp -s "$baseline" "$review_file" ||
    die "the read-only review snapshot was modified; no change was applied to $envrc"
  managed_project_identity "$project_abs" "$workspace" >/dev/null

  chmod 700 "$review_dir"
  rm -rf -- "$review_dir"
  trap - EXIT HUP INT TERM
}

project_fingerprint() {
  [[ $# -le 1 ]] || die "usage: codex-home project-fingerprint [PROJECT_DIR]"
  local project="${1:-.}" project_abs workspace
  [[ -d "$project" ]] || die "project directory does not exist: $project"
  project_abs="$(cd "$project" && pwd -P)"
  workspace="$(managed_project_workspace "$project_abs")"
  managed_project_identity "$project_abs" "$workspace" >/dev/null
  data_helper fingerprint "$project_abs" "$project_abs/.envrc" "$workspace"
}

approve_project_context() {
  [[ $# -eq 2 ]] || die "usage: codex-home project-approve PROJECT_DIR SHA256"
  local project="$1" receipt="$2" before after
  [[ "$receipt" =~ ^[a-f0-9]{64}$ ]] || die "invalid review fingerprint"
  before="$(project_fingerprint "$project")" || return
  [[ "$before" == "$receipt" ]] || die "project changed since review; review it again before approval"
  direnv allow "$project" || return
  if ! after="$(project_fingerprint "$project")" || [[ "$after" != "$receipt" ]]; then
    revoke_project_approval "$project"
    die "project changed during approval; approval revoked; review it again"
  fi
}

project_direnv_exec() {
  local project_dir="$1" launch_status
  shift
  # Older direnv releases also silence log_error when this format is empty.
  # Keep diagnostics visible and stream the command's output without buffering.
  if env -u CODEX_IDENTITY -u CODEX_HOME \
    -u DIRENV_DIFF -u DIRENV_DIR -u DIRENV_FILE -u DIRENV_WATCHES \
    DIRENV_LOG_FORMAT="${DIRENV_LOG_FORMAT:-direnv: %s}" \
    direnv exec "$project_dir" "$@"; then
    return 0
  else
    launch_status=$?
  fi
  printf 'codex-home: failed to launch project: %s (exit %s)\n' "$project_dir" "$launch_status" >&2
  printf '%s\n' "codex-home: verify the project's .envrc, required commands, and VS Code CLI; see the diagnostic above" >&2
  return "$launch_status"
}

project_launch_home() {
  local project="$1" default_home="$2"
  local name="${CODEX_IDENTITY:-}" selected_home="${CODEX_HOME:-}" expected_home
  [[ -n "$name" && -n "$selected_home" ]] ||
    die "direnv did not load a Codex identity from $project/.envrc; check direnv status for denied approval or a skipped file"
  if [[ "$name" == default ]]; then
    expected_home="$default_home"
  else
    expected_home="$(identity_home "$name")"
  fi
  ensure_identity "$name" "$expected_home"
  [[ -d "$selected_home" ]] || die "project's CODEX_HOME does not exist: $selected_home"
  [[ "$(cd "$selected_home" && pwd -P)" == "$(cd "$expected_home" && pwd -P)" ]] ||
    die "project selects identity '$name' but CODEX_HOME is '$selected_home'; expected '$expected_home'"
  printf '%s\n' "$expected_home"
}

check_project_selection() {
  local active_name="$1" active_home="$2" cursor="$PWD" expected expected_home
  # Read recognized templates as data. A custom .envrc may choose its context
  # dynamically, so leave its verification to the approved launch path.
  while :; do
    if [[ -e "$cursor/.envrc" || -L "$cursor/.envrc" ]]; then
      expected="$(generated_project_identity "$cursor/.envrc" 2>/dev/null)" || return 0
      expected_home="$(identity_home "$expected")"
      if [[ -d "$expected_home" ]]; then
        expected_home="$(cd "$expected_home" && pwd -P)" || return
      fi
      if [[ -d "$active_home" ]]; then
        active_home="$(cd "$active_home" && pwd -P)" || return
      fi
      if [[ "$active_name" != "$expected" || "$active_home" != "$expected_home" ]]; then
        printf 'codex-home: project selects %s at %s, but this process selects %s at %s.\n' \
          "$expected" "$expected_home" "$active_name" "$active_home" >&2
        printf 'codex-home: enter the approved project with direnv, or open it with codex-home vscode %s "%s".\n' \
          "$expected" "$cursor" >&2
        return 1
      fi
      return 0
    fi
    [[ "$cursor" != / ]] || break
    cursor="$(dirname "$cursor")"
  done
}

