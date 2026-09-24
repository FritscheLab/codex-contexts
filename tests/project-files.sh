#!/usr/bin/env bash
# Project-file checks use temporary identities and never change real approvals.
set -euo pipefail

FILES_TEST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$FILES_TEST_REPO/tests/common.sh"
FILES_TEST_TOOL="$(resolve_codex_home_tool "$FILES_TEST_REPO/bin")"
FILES_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-project-files.XXXXXX")"
FILES_TEST_ROOT="$(cd "$FILES_TEST_ROOT" && pwd -P)"
trap 'rm -rf -- "$FILES_TEST_ROOT"' EXIT
export CODEX_HOMES_ROOT="$FILES_TEST_ROOT/identity homes"
unset CODEX_HOME CODEX_IDENTITY DIRENV_DIFF DIRENV_DIR DIRENV_FILE DIRENV_WATCHES
source "$FILES_TEST_TOOL"

fail() { printf 'Project files test failure: %s\n' "$*" >&2; exit 1; }
expect_failure() {
  local diagnostic="$1"
  shift
  if ( "$@" ) >"$FILES_TEST_ROOT/output" 2>"$FILES_TEST_ROOT/error"; then
    fail "accepted failure: $diagnostic"
  fi
  grep -Fq -- "$diagnostic" "$FILES_TEST_ROOT/error" || {
    cat "$FILES_TEST_ROOT/error" >&2
    fail "missing diagnostic: $diagnostic"
  }
}
direnv() {
  [[ "$1" == deny ]] || return 2
  printf '%s\n' "$2" >"$FILES_TEST_ROOT/denied"
}
make_project() {
  mkdir -p "$1"
  write_project_files files-one "$1" >/dev/null
}
assert_no_staging() {
  [[ -z "$(find "$1" -name '*.codex-home.*' -o -name '.codex-home-backup.*')" ]] ||
    fail "temporary files remain in $1"
}
with_rename_failure() (
  local fail_at="$1" fail_restore="$2" renames=0
  shift 2
  mv() {
    renames=$((renames + 1))
    if [[ "$renames" -eq "$fail_at" ||
      ( "$fail_restore" == 1 && "$renames" -eq 3 ) ]]; then
      printf 'injected rename failure %s\n' "$renames" >&2
      return 71
    fi
    command mv "$@"
  }
  "$@"
)

create_subscription files-one >/dev/null
create_subscription files-two >/dev/null
project="$FILES_TEST_ROOT/ordinary project"
make_project "$project"
workspace="$(project_workspace_path "$project")"

# Ordinary paths keep the previously generated text, including its final newline.
printf '%s\n' \
  "$PROJECT_ENVRC_MARKER" \
  'export CODEX_IDENTITY="files-one"' \
  "export CODEX_HOME=\"$CODEX_HOMES_ROOT/files-one\"" \
  '' \
  'if [[ ! -d "$CODEX_HOME" ]]; then' \
  '  log_error "Missing Codex identity directory: $CODEX_HOME"' \
  '  return 1' \
  'fi' \
  '' \
  'dotenv_if_exists "$CODEX_HOME/.env"' \
  "PATH_add \"$SCRIPT_DIR\"" \
  'watch_file "$CODEX_HOME/config.toml"' \
  'if [[ -f "$CODEX_HOME/.env" ]]; then' \
  '  watch_file "$CODEX_HOME/.env"' \
  'fi' \
  'log_status "Codex identity: FILES-ONE subscription | CODEX_HOME=$CODEX_HOME"' \
  >"$FILES_TEST_ROOT/old-envrc"
cmp -s "$project/.envrc" "$FILES_TEST_ROOT/old-envrc" || fail 'ordinary envrc format changed'
[[ "$(generated_project_identity "$project/.envrc")" == files-one ]] || fail 'ordinary envrc not recognized'
printf '\n' >>"$project/.envrc"
if generated_project_identity "$project/.envrc" >/dev/null; then fail 'accepted modified trailing newline'; fi
cp "$FILES_TEST_ROOT/old-envrc" "$project/.envrc"

# Home/helper quoting is inert, and ownership detection never runs project code.
(
  cd "$FILES_TEST_ROOT"
  CODEX_HOMES_ROOT="$FILES_TEST_ROOT/"'homes "quotes" \ $value $(touch home-dollar) `touch home-backtick`'
  SCRIPT_DIR="$FILES_TEST_ROOT/"'helper "quotes" \ $value $(touch helper-dollar) `touch helper-backtick`'
  mkdir -p "$SCRIPT_DIR"
  create_subscription files-one >/dev/null
  exotic_project="$FILES_TEST_ROOT/"'project "quoted" $literal [one]'
  make_project "$exotic_project"
  bash -n "$exotic_project/.envrc"
  [[ "$(generated_project_identity "$exotic_project/.envrc")" == files-one ]] || fail 'quoted envrc not recognized'
  expected_home="$CODEX_HOMES_ROOT/files-one"
  expected_helper="$SCRIPT_DIR"
  dotenv_if_exists() { :; }
  watch_file() { :; }
  log_status() { :; }
  PATH_add() { loaded_helper="$1"; }
  source "$exotic_project/.envrc"
  [[ "$CODEX_HOME" == "$expected_home" && "$loaded_helper" == "$expected_helper" ]] || fail 'quoted paths changed after loading'
  [[ ! -e home-dollar && ! -e home-backtick && ! -e helper-dollar && ! -e helper-backtick ]] || fail 'path text executed'
  {
    sed '/^PATH_add /d' "$exotic_project/.envrc"
    printf '%s\n' 'PATH_add "$(touch ownership-executed)"'
  } >"$FILES_TEST_ROOT/untrusted-envrc"
  if generated_project_identity "$FILES_TEST_ROOT/untrusted-envrc" >/dev/null; then fail 'accepted executable helper expression'; fi
  [[ ! -e ownership-executed ]] || fail 'ownership check executed project code'
)

# A producer error must fail even when the writer is called from a conditional.
for failure in jq jq-title envrc workspace; do
  (
    case "$failure" in
      jq) jq() { return 7; } ;;
      jq-title)
        jq() {
          [[ "$*" != *CODEX:* ]] || return 7
          command jq "$@"
        }
        ;;
      envrc) render_project_envrc() { printf 'partial envrc\n'; return 7; } ;;
      workspace) render_project_workspace() { printf 'partial workspace\n'; return 7; } ;;
    esac
    expect_failure 'could not render project configuration' write_project_templates files-two "$project"
  )
  cmp -s "$project/.envrc" "$FILES_TEST_ROOT/old-envrc" || fail "$failure failure changed envrc"
  workspace_matches_generated_template "$workspace" files-one "$project" || fail "$failure failure changed workspace"
  assert_no_staging "$project"
done
(
  jq() { return 7; }
  : >"$FILES_TEST_ROOT/empty-workspace"
  if workspace_matches_generated_template "$FILES_TEST_ROOT/empty-workspace" files-one "$project"; then
    fail 'ownership accepted empty output from a failed renderer'
  fi
)

# Failed publication restores either the old pair or the original absence.
for operation in create change; do
  for fail_at in 1 2; do
    failure_project="$FILES_TEST_ROOT/$operation-$fail_at"
    mkdir -p "$failure_project"
    failure_workspace="$(project_workspace_path "$failure_project")"
    if [[ "$operation" == change ]]; then
      make_project "$failure_project"
      cp "$failure_project/.envrc" "$FILES_TEST_ROOT/before-envrc"
      cp "$failure_workspace" "$FILES_TEST_ROOT/before-workspace"
      expect_failure 'could not replace' with_rename_failure "$fail_at" 0 change_project_files files-two "$failure_project"
      cmp -s "$failure_project/.envrc" "$FILES_TEST_ROOT/before-envrc" || fail "change rename $fail_at did not restore envrc"
      cmp -s "$failure_workspace" "$FILES_TEST_ROOT/before-workspace" || fail "change rename $fail_at did not restore workspace"
      [[ "$(managed_project_identity "$failure_project" "$failure_workspace")" == files-one ]] || fail 'restored pair cannot be managed'
      [[ "$(<"$FILES_TEST_ROOT/denied")" == "$failure_project" ]] || fail 'change did not revoke approval'
    else
      expect_failure 'could not replace' with_rename_failure "$fail_at" 0 write_project_files files-one "$failure_project"
      [[ ! -e "$failure_project/.envrc" && ! -e "$failure_workspace" ]] || fail "create rename $fail_at left a partial pair"
    fi
    assert_no_staging "$failure_project"
  done
done

# A failed restoration must retain the original file and its recovery location.
recovery_project="$FILES_TEST_ROOT/failed-restoration"
make_project "$recovery_project"
cp "$recovery_project/.envrc" "$FILES_TEST_ROOT/recovery-original"
expect_failure 'restoration failed; recover original files from' \
  with_rename_failure 2 1 change_project_files files-two "$recovery_project"
backup_dir="$(find "$recovery_project" -maxdepth 1 -type d -name '.codex-home-backup.*')"
[[ -n "$backup_dir" ]] || fail 'failed restoration discarded backups'
cmp -s "$backup_dir/envrc" "$FILES_TEST_ROOT/recovery-original" || fail 'retained backup is not the original envrc'
grep -Fq -- "$backup_dir" "$FILES_TEST_ROOT/error" || fail 'recovery diagnostic omitted backup location'
if ( managed_project_identity "$recovery_project" "$(project_workspace_path "$recovery_project")" ) >/dev/null 2>&1; then
  fail 'partially restored pair was accepted'
fi

# Both old workspace templates migrate while literal exclusions stay scoped.
for marker in 0 1; do
  legacy_project="$FILES_TEST_ROOT/repo-$marker/"'nested [one] \ literal'
  mkdir -p "$legacy_project"
  git -C "$FILES_TEST_ROOT/repo-$marker" init -q
  make_project "$legacy_project"
  legacy_workspace="$(legacy_project_workspace_path "$legacy_project")"
  rm -f "$(project_workspace_path "$legacy_project")"
  render_legacy_project_workspace files-one "$marker" >"$legacy_workspace"
  details="$(project_git_exclude_details "$legacy_project")"
  {
    IFS= read -r exclude_file
    IFS= read -r envrc_pattern
    IFS= read -r workspace_pattern
    IFS= read -r legacy_pattern
  } <<< "$details"
  printf '%s\n' "$legacy_pattern" '/unrelated-path' >>"$exclude_file"
  expect_failure 'could not replace' with_rename_failure 2 0 change_project_files files-two "$legacy_project"
  [[ "$(managed_project_identity "$legacy_project" "$legacy_workspace")" == files-one ]] || fail 'failed migration did not restore the old pair'
  [[ ! -e "$(project_workspace_path "$legacy_project")" ]] || fail 'failed migration left a named workspace'
  assert_no_staging "$legacy_project"
  change_project_files files-two "$legacy_project" >/dev/null
  [[ ! -e "$legacy_workspace" ]] || fail 'migration left the generic workspace'
  [[ "$(managed_project_identity "$legacy_project" "$(project_workspace_path "$legacy_project")")" == files-two ]] || fail 'migration did not create a manageable pair'
  grep -Fqx -- "$envrc_pattern" "$exclude_file" || fail 'migration removed envrc exclusion'
  grep -Fqx -- "$workspace_pattern" "$exclude_file" || fail 'migration removed named workspace exclusion'
  if grep -Fqx -- "$legacy_pattern" "$exclude_file"; then fail 'migration left the old exclusion'; fi
  grep -Fqx '/unrelated-path' "$exclude_file" || fail 'migration removed an unrelated exclusion'
  reset_project_files "$legacy_project" >/dev/null
  if grep -Fqx -- "$envrc_pattern" "$exclude_file" || grep -Fqx -- "$workspace_pattern" "$exclude_file"; then
    fail 'reset left project exclusions'
  fi
  grep -Fqx '/unrelated-path' "$exclude_file" || fail 'reset removed an unrelated exclusion'
done

printf 'Project files tests passed.\n'
