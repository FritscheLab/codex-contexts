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

# Ordinary paths keep an exact, credential-free template with its final newline.
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
  "PATH_add \"$SCRIPT_DIR\"" \
  'watch_file "$CODEX_HOME/config.toml"' \
  'if [[ -f "$CODEX_HOME/api-key.env" ]]; then' \
  '  watch_file "$CODEX_HOME/api-key.env"' \
  'fi' \
  'if [[ -f "$CODEX_HOME/.env" ]]; then' \
  '  watch_file "$CODEX_HOME/.env"' \
  'fi' \
  'log_status "Codex identity: FILES-ONE subscription | CODEX_HOME=$CODEX_HOME"' \
  >"$FILES_TEST_ROOT/old-envrc"
cmp -s "$project/.envrc" "$FILES_TEST_ROOT/old-envrc" || fail 'ordinary envrc format changed'
[[ "$(generated_project_identity "$project/.envrc")" == files-one ]] || fail 'ordinary envrc not recognized'
render_project_envrc files-one "$SCRIPT_DIR" 1 >"$FILES_TEST_ROOT/legacy-envrc"
[[ "$(generated_project_identity "$FILES_TEST_ROOT/legacy-envrc")" == files-one ]] || fail 'legacy envrc cannot be safely migrated'
render_project_envrc files-one "$SCRIPT_DIR" 0 1 >"$FILES_TEST_ROOT/old-watch-envrc"
[[ "$(generated_project_identity "$FILES_TEST_ROOT/old-watch-envrc")" == files-one ]] || fail 'old key-file watch template cannot be migrated'
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
  workspace_matches_generated_template "$workspace" files-one || fail "$failure failure changed workspace"
  assert_no_staging "$project"
done
(
  jq() { return 7; }
  : >"$FILES_TEST_ROOT/empty-workspace"
  if workspace_matches_generated_template "$FILES_TEST_ROOT/empty-workspace" files-one; then
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
  details="$(project_git_exclude_details "$legacy_project" "$(project_workspace_path "$legacy_project")")"
  {
    IFS= read -r exclude_file
    IFS= read -r envrc_pattern
    IFS= read -r workspace_pattern
  } <<< "$details"
  legacy_pattern="$(project_git_exclude_details "$legacy_project" "$legacy_workspace" | tail -1)"
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
  grep -Fqx -- "$legacy_pattern" "$exclude_file" || fail 'migration removed an unmarked legacy rule'
  grep -Fqx '/unrelated-path' "$exclude_file" || fail 'migration removed an unrelated exclusion'
  reset_project_files "$legacy_project" >/dev/null
  if grep -Fqx -- "$envrc_pattern" "$exclude_file" || grep -Fqx -- "$workspace_pattern" "$exclude_file"; then
    fail 'reset left project exclusions'
  fi
  grep -Fqx '/unrelated-path' "$exclude_file" || fail 'reset removed an unrelated exclusion'
done

# Effective Git rules can differ from the rules written to info/exclude.
negated_project="$FILES_TEST_ROOT/negated"
mkdir -p "$negated_project"
git -C "$negated_project" init -q
printf '%s\n' '!/.envrc' '!/.vscode/negated.code-workspace' >"$negated_project/.gitignore"
write_project_files files-one "$negated_project" >"$FILES_TEST_ROOT/output" 2>"$FILES_TEST_ROOT/error"
grep -Fq 'Git does not ignore .envrc' "$FILES_TEST_ROOT/error" || fail 'no diagnostic for unignored envrc'
grep -Fq 'Git does not ignore .vscode/negated.code-workspace' "$FILES_TEST_ROOT/error" ||
  fail 'no diagnostic for unignored workspace'
if grep -Fq 'generated files are ignored' "$FILES_TEST_ROOT/output"; then fail 'falsely reported Git protection'; fi
[[ -f "$negated_project/.envrc" ]] || fail 'Git warning damaged project setup'

# Reset may remove only exact rules inserted by this helper, even when a
# preexisting rule is identical or a user later adds a duplicate.
preserved_project="$FILES_TEST_ROOT/user-rules"
mkdir -p "$preserved_project"
git -C "$preserved_project" init -q
printf '%s\n' '# Owner rules' '/.envrc' '/.vscode/codex-context.code-workspace' \
  >"$preserved_project/.git/info/exclude"
make_project "$preserved_project"
printf '%s\n' '/.vscode/user-rules.code-workspace' >>"$preserved_project/.git/info/exclude"
reset_project_files "$preserved_project" >/dev/null
printf '%s\n' '# Owner rules' '/.envrc' '/.vscode/codex-context.code-workspace' \
  '/.vscode/user-rules.code-workspace' >"$FILES_TEST_ROOT/owner-excludes"
cmp -s "$FILES_TEST_ROOT/owner-excludes" "$preserved_project/.git/info/exclude" ||
  fail 'reset changed rules it did not add'

# info/exclude belongs to the common Git directory, so resetting one worktree
# must not expose the identically located envrc in the other checkout.
shared_main="$FILES_TEST_ROOT/main-worktree"
shared_link="$FILES_TEST_ROOT/linked-worktree"
mkdir "$shared_main"
git -C "$shared_main" init -q
git -C "$shared_main" -c user.name=Fixture -c user.email=fixture@example.test -c commit.gpgSign=false -c core.hooksPath=/dev/null \
  commit --allow-empty --quiet -m initial
git -C "$shared_main" worktree add --detach --quiet "$shared_link"
make_project "$shared_main"
make_project "$shared_link"
reset_project_files "$shared_main" >"$FILES_TEST_ROOT/output"
grep -Fq 'kept shared exclude rules for linked worktrees' "$FILES_TEST_ROOT/output" ||
  fail 'reset omitted shared exclude status'
git -C "$shared_link" check-ignore -q -- .envrc || fail 'reset exposed the linked worktree envrc'

# Pause reset after it has prepared its exclude replacement. A different
# project's setup must share the lock and keep its new rules after reset.
wait_for_file() {
  local path="$1" attempt
  for ((attempt = 0; attempt < 200; attempt++)); do
    [[ ! -e "$path" ]] || return 0
    sleep 0.025
  done
  fail "timed out waiting for $(basename "$path")"
}
shared_repo="$FILES_TEST_ROOT/shared-repo"
previous_project="$shared_repo/previous"
another_project="$shared_repo/another"
mkdir -p "$previous_project" "$another_project"
git -C "$shared_repo" init -q
make_project "$previous_project"
(
  mv() {
    if [[ "$2" == */info/exclude ]]; then
      touch "$shared_repo/reset-ready"
      wait_for_file "$shared_repo/publish"
    fi
    command mv "$@"
  }
  reset_project_files "$previous_project" >/dev/null
) &
reset_pid=$!
wait_for_file "$shared_repo/reset-ready"
if ( macos_acquire_locks --timeout 0 "$shared_repo/.git/info/.codex-contexts-exclude.lock" ) 2>/dev/null; then
  fail 'reset did not hold the exclude lock through publication'
fi
(
  macos_data_helper() {
    [[ "$1" != lock ]] || touch "$shared_repo/setup-ready"
    python3 -I "$CODEX_CONTEXTS_LIB/macos_bundles.py" "$@"
  }
  make_project "$another_project"
) &
setup_pid=$!
wait_for_file "$shared_repo/setup-ready"
touch "$shared_repo/publish"
wait "$reset_pid" || fail 'concurrent reset failed'
wait "$setup_pid" || fail 'concurrent setup failed'
git -C "$another_project" check-ignore -q -- .envrc || fail 'reset overwrote concurrent setup rules'
git -C "$another_project" check-ignore -q -- .vscode/another.code-workspace ||
  fail 'concurrent setup workspace is unignored'

# Repair a renamed root or nested project. Rebuild the label, keep customized
# workspaces, and replace only known stale rules.
for location in root nested; do
  repo="$FILES_TEST_ROOT/rename-$location"
  old_project="$repo"
  if [[ "$location" == nested ]]; then old_project="$repo/parent/old [name]"; fi
  mkdir -p "$old_project"
  git -C "$repo" init -q
  make_project "$old_project"
  old_workspace="$(project_workspace_path "$old_project")"
  old_workspace_name="$(basename "$old_workspace")"
  old_pattern="$(project_git_exclude_details "$old_project" "$old_workspace" | tail -1)"
  renamed="$(dirname "$old_project")/new $location"
  mv "$old_project" "$renamed"
  previous="$renamed/.vscode/$old_workspace_name"
  printf '%s\n' 'custom workspace' >"$renamed/.vscode/custom.code-workspace"
  printf '\n' >>"$previous"
  expect_failure 'manual recovery in docs/projects-vscode.md' change_project_files files-two "$renamed"
  [[ -f "$previous" && ! -e "$(project_workspace_path "$renamed")" ]] ||
    fail 'rename repair replaced a customized workspace'
  render_project_workspace files-one "${old_workspace_name%.code-workspace}" >"$previous"
  git -C "$renamed" add -f -- ".vscode/$old_workspace_name"
  expect_failure 'already tracked by Git' change_project_files files-two "$renamed"
  git -C "$renamed" rm --cached -q -- ".vscode/$old_workspace_name"
  change_project_files files-two "$renamed" >/dev/null
  [[ ! -e "$previous" && "$(<"$renamed/.vscode/custom.code-workspace")" == 'custom workspace' ]] ||
    fail 'rename repair removed the wrong workspace'
  [[ "$(generated_project_identity "$renamed/.envrc")" == files-two ]] || fail 'renamed envrc has wrong identity'
  grep -Fq -- "[CODEX: FILES-TWO]" "$(project_workspace_path "$renamed")" || fail 'renamed workspace has wrong label'
  git -C "$renamed" check-ignore -q -- .envrc || fail 'renamed envrc is not ignored'
  git -C "$renamed" check-ignore -q -- "$(project_workspace_git_path "$renamed")" ||
    fail 'renamed workspace is not ignored'
  exclude_file="$(cd "$renamed" && git rev-parse --path-format=absolute --git-path info/exclude)"
  if grep -Fqx -- "$old_pattern" "$exclude_file"; then fail 'repair left its old workspace rule'; fi
  if [[ "$location" == nested ]] && grep -Fq -- 'old \[name]/.envrc' "$exclude_file"; then
    fail 'repair left its old envrc rule'
  fi
done

printf 'Project files tests passed.\n'
