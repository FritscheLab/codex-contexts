#!/usr/bin/env bash
# Project templates, ownership, Git exclusions, review, and direnv approval.

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
  local path
  path="$(project_workspace_git_path "$project_abs")" || return
  printf '%s/%s\n' "$project_abs" "$path"
}

legacy_project_workspace_path() {
  local project_abs="$1"
  printf '%s/.vscode/codex-context.code-workspace\n' "$project_abs"
}

ensure_project_files_untracked() {
  local project_abs="$1"
  local workspace="$2"
  local workspace_rel
  if [[ "$(git -C "$project_abs" rev-parse --is-inside-work-tree 2>/dev/null)" != true ]]; then
    return 0
  fi
  workspace_rel="${workspace#"$project_abs/"}"
  [[ "$workspace_rel" != "$workspace" ]] ||
    die "VS Code workspace is outside the project: $workspace"
  if git -C "$project_abs" ls-files --error-unmatch -- .envrc >/dev/null 2>&1; then
    die "refusing to manage .envrc because that path is already tracked by Git"
  fi
  if git -C "$project_abs" --literal-pathspecs ls-files --error-unmatch -- "$workspace_rel" \
    >/dev/null 2>&1; then
    die "refusing to manage $workspace_rel because that path is already tracked by Git"
  fi
}

project_git_exclude_details() {
  local project_abs="$1" workspace="$2" previous_name="${3:-}"
  local project_prefix exclude_file workspace_rel

  project_prefix="$(git -C "$project_abs" rev-parse --show-prefix)" ||
    return
  exclude_file="$(cd "$project_abs" && git rev-parse --git-path info/exclude)" ||
    return
  if [[ "$exclude_file" != /* ]]; then
    exclude_file="$project_abs/$exclude_file"
  fi
  if [[ -n "$previous_name" && -n "$project_prefix" ]]; then
    # A renamed folder still sits under the same Git-relative parent.
    project_prefix="$(dirname "${project_prefix%/}")"
    if [[ "$project_prefix" == . ]]; then project_prefix=""; else project_prefix="$project_prefix/"; fi
    project_prefix="$project_prefix$previous_name/"
  fi
  workspace_rel="${workspace#"$project_abs/"}"
  printf '%s\n' "$exclude_file"
  printf '/%s\n' "$(gitignore_escape_literal "${project_prefix}.envrc")"
  printf '/%s\n' "$(gitignore_escape_literal "$project_prefix$workspace_rel")"
}

lock_project_git_excludes() {
  local exclude_file="$1" info_directory
  [[ ! -L "$exclude_file" && ( ! -e "$exclude_file" || -f "$exclude_file" ) ]] || return 1
  info_directory="$(dirname "$exclude_file")"
  mkdir -p "$info_directory" || return
  # The bundle helper's advisory file lock uses fcntl on macOS and Linux.
  macos_acquire_locks --timeout 5 "$info_directory/.codex-contexts-exclude.lock"
}

add_project_git_excludes() (
  local project_abs="$1" workspace="$2"
  local details exclude_file envrc_pattern workspace_pattern path pattern ignored=1

  if [[ "$(git -C "$project_abs" rev-parse --is-inside-work-tree 2>/dev/null)" != true ]]; then
    printf '  Git:      outside a Git work tree\n'
    return 0
  fi

  details="$(project_git_exclude_details "$project_abs" "$workspace")" || return
  {
    IFS= read -r exclude_file
    IFS= read -r envrc_pattern
    IFS= read -r workspace_pattern
  } <<< "$details"

  lock_project_git_excludes "$exclude_file" || return
  for path in .envrc "${workspace#"$project_abs/"}"; do
    if git -C "$project_abs" check-ignore -q -- "$path"; then continue; fi
    if [[ "$path" == .envrc ]]; then pattern="$envrc_pattern"; else pattern="$workspace_pattern"; fi
    if ! grep -Fqx -- "$pattern" "$exclude_file" 2>/dev/null; then
      if [[ -s "$exclude_file" && -n "$(tail -c 1 "$exclude_file")" ]]; then
        printf '\n' >> "$exclude_file" || return
      fi
      printf '# codex-home: %s\n%s\n' "$pattern" "$pattern" >> "$exclude_file" || return
    fi
    if ! git -C "$project_abs" check-ignore -q -- "$path"; then
      printf 'codex-home: Git does not ignore %q. Check its .gitignore rules before staging this machine-local file.\n' "$path" >&2
      ignored=0
    fi
  done
  if [[ "$ignored" == 1 ]]; then
    printf '  Git:      generated files are ignored\n'
  fi
)

remove_project_git_excludes() (
  local project_abs="$1" workspace="$2" mode="${3:-reset}" previous_name="${4:-}"
  local details exclude_file envrc_pattern workspace_pattern exclude_tmp worktrees

  if [[ "$(git -C "$project_abs" rev-parse --is-inside-work-tree 2>/dev/null)" != true ]]; then
    return 0
  fi

  details="$(project_git_exclude_details "$project_abs" "$workspace" "$previous_name")" || return
  {
    IFS= read -r exclude_file
    IFS= read -r envrc_pattern
    IFS= read -r workspace_pattern
  } <<< "$details"
  [[ -f "$exclude_file" && ! -L "$exclude_file" ]] || return 0
  lock_project_git_excludes "$exclude_file" || return
  # Migration keeps the existing envrc rule when the Git-relative folder did not move.
  if [[ ( "$mode" == migration && -z "$previous_name" ) ||
    ( -n "$previous_name" && -z "$(git -C "$project_abs" rev-parse --show-prefix)" ) ]]; then
    envrc_pattern=""
  fi
  grep -Fqx -- "# codex-home: $workspace_pattern" "$exclude_file" ||
    { [[ -n "$envrc_pattern" ]] && grep -Fqx -- "# codex-home: $envrc_pattern" "$exclude_file"; } ||
    return 0

  # Git shares info/exclude across linked checkouts. Another checkout can rely
  # on the same relative path even if this one has removed the generated file.
  worktrees="$(git -C "$project_abs" worktree list --porcelain)" || return
  if [[ "$(grep -c '^worktree ' <<< "$worktrees")" -gt 1 ]]; then
    printf '  Git:      kept shared exclude rules for linked worktrees\n'
    return 0
  fi

  exclude_tmp="$(mktemp "${exclude_file}.codex-home.XXXXXX")" || return
  if ! CODEX_ENVRC_PATTERN="$envrc_pattern" CODEX_WORKSPACE_PATTERN="$workspace_pattern" \
    awk '
      BEGIN { envrc = ENVIRON["CODEX_ENVRC_PATTERN"]; workspace = ENVIRON["CODEX_WORKSPACE_PATTERN"] }
      pending {
        if ($0 == pattern) { pending = ""; next }
        print pending
        pending = ""
      }
      $0 == "# codex-home: " workspace || (envrc != "" && $0 == "# codex-home: " envrc) {
        pending = $0
        pattern = $0 == "# codex-home: " workspace ? workspace : envrc
        next
      }
      { print }
      END { if (pending) print pending }
    ' "$exclude_file" > "$exclude_tmp"; then
    rm -f "$exclude_tmp"
    return 1
  fi
  if ! mv "$exclude_tmp" "$exclude_file"; then
    rm -f "$exclude_tmp"
    return 1
  fi
)

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
  local previous_workspace="${3:-}"
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
      if [[ -n "$previous_workspace" && ! -e "$previous_workspace" && ! -L "$previous_workspace" ]]; then
        mv "$backup_dir/previous-workspace" "$previous_workspace" || keep_backups=1
      fi
    fi
    [[ -z "$envrc_tmp" ]] || rm -f "$envrc_tmp"
    [[ -z "$workspace_tmp" ]] || rm -f "$workspace_tmp"
    if [[ -n "$backup_dir" ]]; then
      if [[ "$keep_backups" == 1 ]]; then
        printf 'codex-home: restoration failed; recover original files from %s before reopening this project\n' "$backup_dir" >&2
        status=1
      else
        rm -f "$backup_dir/envrc" "$backup_dir/workspace" "$backup_dir/previous-workspace"
        rmdir "$backup_dir"
      fi
    fi
    exit "$status"
  }

  project_name="$(basename "$project_abs")" || return
  workspace="$(project_workspace_path "$project_abs")" || return
  if [[ "$previous_workspace" == "$workspace" ]]; then previous_workspace=""; fi
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
  if [[ -n "$previous_workspace" ]]; then
    cp -p "$previous_workspace" "$backup_dir/previous-workspace" || die "could not back up $previous_workspace"
  fi
  restore=1
  mv "$envrc_tmp" "$envrc" || die "could not replace $envrc"
  mv "$workspace_tmp" "$workspace" || die "could not replace $workspace"
  if [[ -n "$previous_workspace" ]]; then
    rm -f -- "$previous_workspace" || die "could not remove previous workspace: $previous_workspace"
  fi
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
  local project_name expected

  [[ -f "$workspace" && ! -L "$workspace" ]] || return 1
  project_name="$(basename "$workspace" .code-workspace)"
  expected="$(render_project_workspace "$name" "$project_name")" || return 1
  if cmp -s "$workspace" <(printf '%s\n' "$expected"); then return 0; fi
  expected="$(render_legacy_project_workspace "$name")" || return 1
  cmp -s "$workspace" <(printf '%s\n' "$expected") ||
    cmp -s "$workspace" <(printf '%s\n' "${expected#*$'\n'}")
}

managed_project_workspace() {
  local project_abs="$1"
  local repair="${2:-}"
  local workspace legacy_workspace name candidate found=""
  workspace="$(project_workspace_path "$project_abs")" || return
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
  elif [[ "$repair" == repair && ! -L "$project_abs/.vscode" ]] &&
    name="$(generated_project_identity "$project_abs/.envrc")"; then
    # A folder rename leaves the original generated title and workspace name.
    for candidate in "$project_abs/.vscode/"*.code-workspace "$project_abs/.vscode/."*.code-workspace; do
      [[ "$candidate" != "$found" ]] || continue
      workspace_matches_generated_template "$candidate" "$name" || continue
      [[ -z "$found" ]] ||
        die "found multiple previous workspaces; use manual recovery in docs/projects-vscode.md"
      found="$candidate"
    done
    printf '%s\n' "${found:-$workspace}"
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
    die "refusing to replace $envrc because it does not exactly match a generated codex-home file; see manual recovery in docs/projects-vscode.md"
  workspace_matches_generated_template "$workspace" "$name" ||
    die "refusing to replace $workspace because it does not exactly match a generated codex-home file; see manual recovery in docs/projects-vscode.md"
  ensure_project_files_untracked "$project_abs" "$workspace"
  printf '%s\n' "$name"
}

print_project_next_steps() {
  local name="$1" project_abs="$2"
  printf 'Read the generated shell file before approving it:\n'
  printf '  cat %q\n' "$project_abs/.envrc"
  printf 'If you understand the file, allow direnv to run it with your user permissions:\n'
  printf '  direnv allow %q\n' "$project_abs"
  printf 'Then open this project in VS Code or start a terminal session:\n'
  printf '  %q vscode %q %q\n' "$CODEX_CONTEXTS_LAUNCHER" "$name" "$project_abs"
  printf '  cd %q && %q run %q\n' "$project_abs" "$CODEX_CONTEXTS_LAUNCHER" "$name"
}

write_project_files() {
  [[ $# -ge 1 && $# -le 2 ]] || die "usage: codex-home project NAME [PROJECT_DIR]"
  local name="$1"
  local project_dir="${2:-.}"
  local project_abs envrc workspace legacy_workspace
  ensure_identity "$name"
  [[ -d "$project_dir" ]] || die "project directory does not exist: $project_dir"
  project_abs="$(cd "$project_dir" && pwd -P)"
  validate_single_line "project path" "$project_abs"
  envrc="$project_abs/.envrc"
  workspace="$(project_workspace_path "$project_abs")" || return
  legacy_workspace="$(legacy_project_workspace_path "$project_abs")"

  [[ ! -e "$envrc" && ! -L "$envrc" ]] ||
    die "refusing to overwrite existing $envrc (see docs/projects-vscode.md for the block to add manually)"
  [[ ! -e "$workspace" && ! -L "$workspace" ]] ||
    die "refusing to overwrite existing $workspace"
  if [[ "$legacy_workspace" != "$workspace" ]]; then
    [[ ! -e "$legacy_workspace" && ! -L "$legacy_workspace" ]] ||
      die "refusing to replace existing workspace $legacy_workspace"
  fi
  if [[ -e "$project_abs/.vscode" || -L "$project_abs/.vscode" ]]; then
    [[ -d "$project_abs/.vscode" && ! -L "$project_abs/.vscode" ]] ||
      die "refusing to use $project_abs/.vscode because it is not a regular directory"
  fi

  ensure_project_files_untracked "$project_abs" "$workspace"
  write_project_templates "$name" "$project_abs" || return

  printf 'Configured %s for %s\n' "$project_abs" "$(identity_label "$name")"
  printf '  direnv:   %s\n' "$envrc"
  printf '  VS Code:  %s\n' "$workspace"
  add_project_git_excludes "$project_abs" "$workspace" ||
    printf 'codex-home: could not add Git exclusions; check git status before staging the generated files.\n' >&2
  print_project_next_steps "$name" "$project_abs"
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
  local project_abs previous_name workspace new_workspace previous_folder=""
  ensure_identity "$name"
  command -v direnv >/dev/null 2>&1 || die "direnv is not installed"
  [[ -d "$project_dir" ]] || die "project directory does not exist: $project_dir"
  project_abs="$(cd "$project_dir" && pwd -P)"
  validate_single_line "project path" "$project_abs"
  workspace="$(managed_project_workspace "$project_abs" repair)" || return
  previous_name="$(managed_project_identity "$project_abs" "$workspace")" || return
  new_workspace="$(project_workspace_path "$project_abs")" || return
  if [[ "$workspace" != "$new_workspace" ]]; then
    [[ ! -e "$new_workspace" && ! -L "$new_workspace" ]] ||
      die "refusing to overwrite existing $new_workspace"
    ensure_project_files_untracked "$project_abs" "$new_workspace"
    if [[ "$workspace" != "$(legacy_project_workspace_path "$project_abs")" ]]; then
      previous_folder="$(basename "$workspace" .code-workspace)"
      # Retain rules for an existing sibling, which can be the source of a copy.
      if [[ -e "$(dirname "$project_abs")/$previous_folder" ||
        -L "$(dirname "$project_abs")/$previous_folder" ]]; then
        previous_folder=""
      fi
    fi
  fi

  revoke_project_approval "$project_abs"
  write_project_templates "$name" "$project_abs" "$workspace" || return
  if [[ "$workspace" != "$new_workspace" ]]; then
    remove_project_git_excludes "$project_abs" "$workspace" migration "$previous_folder" ||
      printf 'codex-home: could not remove old Git exclusions; see docs/remove-folder-context.md.\n' >&2
  fi

  printf 'Changed %s from %s to %s.\n' "$project_abs" "$previous_name" "$(identity_label "$name")"
  printf '  direnv:   %s/.envrc (approval revoked; review before allowing)\n' "$project_abs"
  printf '  VS Code:  %s\n' "$new_workspace"
  add_project_git_excludes "$project_abs" "$new_workspace" ||
    printf 'codex-home: could not add Git exclusions; check git status before staging the generated files.\n' >&2
  print_project_next_steps "$name" "$project_abs"
}

reset_project_files() {
  [[ $# -le 1 ]] || die "usage: codex-home project-reset [PROJECT_DIR]"
  local project_dir="${1:-.}"
  local project_abs previous_name workspace
  command -v direnv >/dev/null 2>&1 || die "direnv is not installed"
  [[ -d "$project_dir" ]] || die "project directory does not exist: $project_dir"
  project_abs="$(cd "$project_dir" && pwd -P)"
  validate_single_line "project path" "$project_abs"
  workspace="$(managed_project_workspace "$project_abs")" || return
  previous_name="$(managed_project_identity "$project_abs" "$workspace")" || return

  revoke_project_approval "$project_abs"
  rm -f "$project_abs/.envrc" "$workspace"
  rmdir "$project_abs/.vscode" >/dev/null 2>&1 || true
  remove_project_git_excludes "$project_abs" "$workspace" ||
    printf 'codex-home: could not remove Git exclusions; see docs/remove-folder-context.md.\n' >&2

  printf 'Removed generated Codex project context for %s (was %s).\n' \
    "$project_abs" "$previous_name"
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
  workspace="$(managed_project_workspace "$project_abs")" || return
  name="$(managed_project_identity "$project_abs" "$workspace")" || return
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
  workspace="$(managed_project_workspace "$project_abs")" || return
  managed_project_identity "$project_abs" "$workspace" >/dev/null || return
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
  local active_name="$1" active_home="$2" cursor="${3:-$PWD}" expected expected_home
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

