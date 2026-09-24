#!/usr/bin/env bash
# Offline launch checks; all identities, approvals, and CLI calls are isolated.
set -euo pipefail

LAUNCH_TEST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$LAUNCH_TEST_REPO/tests/common.sh"
LAUNCH_TEST_TOOL="$(resolve_codex_home_tool "$LAUNCH_TEST_REPO/bin")"
LAUNCH_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-project-launch.XXXXXX")"
LAUNCH_TEST_ROOT="$(cd "$LAUNCH_TEST_ROOT" && pwd -P)"
trap 'rm -rf -- "$LAUNCH_TEST_ROOT"' EXIT
export CODEX_HOMES_ROOT="$LAUNCH_TEST_ROOT/identity homes"
export DIRENV_CONFIG="$LAUNCH_TEST_ROOT/direnv-config"
export XDG_DATA_HOME="$LAUNCH_TEST_ROOT/xdg-data"
export CODEX_SKILLS_SOURCE="$LAUNCH_TEST_ROOT/empty-skills"
export CODEX_VSCODE_CLI="$LAUNCH_TEST_ROOT/fake bin/code"
export CODEX_VSCODE_EXTENSIONS_DIR="$LAUNCH_TEST_ROOT/extensions"
export CODEX_VSCODE_DOCK_LABEL=0
export CODEX_MACOS_SKIP_REGISTER=1
export CODEX_LAUNCH_TEST_ARGS="$LAUNCH_TEST_ROOT/args"
export CODEX_LAUNCH_TEST_ENV="$LAUNCH_TEST_ROOT/environment"
export CODEX_LAUNCH_TEST_DETAILS="$LAUNCH_TEST_ROOT/details"
export CODEX_LAUNCH_TEST_LOADS="$LAUNCH_TEST_ROOT/loads"
unset CODEX_HOME CODEX_IDENTITY DIRENV_DIFF DIRENV_DIR DIRENV_FILE DIRENV_WATCHES
source "$LAUNCH_TEST_TOOL"

fail() { printf 'Project launch test failure: %s\n' "$*" >&2; exit 1; }
quiet_check() {
  local command_status
  if "$@" >"$LAUNCH_TEST_ROOT/output" 2>&1; then
    return 0
  else
    command_status=$?
  fi
  printf 'Project launch test failure: command failed (exit %s):' "$command_status" >&2
  printf ' %q' "$@" >&2
  printf '\n' >&2
  cat "$LAUNCH_TEST_ROOT/output" >&2
  exit 1
}
expect_rejection() {
  local diagnostic="$1"
  shift
  rm -f "$CODEX_LAUNCH_TEST_ARGS"
  if "$@" >"$LAUNCH_TEST_ROOT/output" 2>"$LAUNCH_TEST_ROOT/error"; then
    fail "accepted invalid project: $diagnostic"
  fi
  grep -Fq -- "$diagnostic" "$LAUNCH_TEST_ROOT/error" || {
    cat "$LAUNCH_TEST_ROOT/error" >&2
    fail "missing diagnostic: $diagnostic"
  }
  [[ ! -e "$CODEX_LAUNCH_TEST_ARGS" ]] || fail 'CLI ran for rejected project'
}
approve_fixture() { direnv allow "$project" >/dev/null 2>&1; }
write_fixture() {
  printf 'export CODEX_IDENTITY=%q\nexport CODEX_HOME=%q\n' "$1" "$2" >"$project/.envrc"
}

mkdir -p "$(dirname "$CODEX_VSCODE_CLI")" "$CODEX_SKILLS_SOURCE" "$CODEX_VSCODE_EXTENSIONS_DIR"
cat >"$CODEX_VSCODE_CLI" <<'EOF'
#!/bin/bash
set -eu
printf '%s\n' "$@" >"$CODEX_LAUNCH_TEST_ARGS"
printf '%s\n%s\n' "${CODEX_IDENTITY:-}" "${CODEX_HOME:-}" >"$CODEX_LAUNCH_TEST_ENV"
printf '%s\n%s\n' "$PWD" "${CODEX_LAUNCH_TEST_NONCE:-}" >"$CODEX_LAUNCH_TEST_DETAILS"
exit "${CODEX_LAUNCH_TEST_EXIT:-0}"
EOF
chmod +x "$CODEX_VSCODE_CLI"
create_subscription launch-unit >/dev/null
create_subscription launch-other >/dev/null
unit_home="$CODEX_HOMES_ROOT/launch-unit"
other_home="$CODEX_HOMES_ROOT/launch-other"
project="$LAUNCH_TEST_ROOT/"'project $one [x]'
mkdir -p "$project"
write_project_files launch-unit "$project" >/dev/null
approve_fixture

quiet_check "$LAUNCH_TEST_TOOL" vscode-project "$project" >/dev/null
grep -Fxq -- "$unit_home/vscode-user-data" "$CODEX_LAUNCH_TEST_ARGS" || fail 'wrong user-data path'
grep -Fxq -- "$project/.vscode/project \$one [x].code-workspace" "$CODEX_LAUNCH_TEST_ARGS" || fail 'project path was split or expanded'
[[ "$(head -n 1 "$CODEX_LAUNCH_TEST_ENV")" == launch-unit ]] || fail 'wrong launched identity'
[[ "$(tail -n 1 "$CODEX_LAUNCH_TEST_ENV")" == "$unit_home" ]] || fail 'wrong launched home'
[[ "$(head -n 1 "$CODEX_LAUNCH_TEST_DETAILS")" == "$project" ]] || fail 'wrong editor working directory'
expect_rejection "project selects 'launch-unit', not 'launch-other'" \
  "$LAUNCH_TEST_TOOL" vscode launch-other "$project"

# Environment errors stay visible even when the caller silences direnv logs.
# Both public launch commands must preserve failure status and skip the editor.
write_fixture launch-unit "$unit_home"
cat >>"$project/.envrc" <<'EOF'
printf 'fixture setup output\n'
log_error 'fixture required-tool is missing'
exit 42
EOF
approve_fixture
for launch_command in vscode-project vscode; do
  launch_args=("$launch_command")
  [[ "$launch_command" != vscode ]] || launch_args+=(launch-unit)
  launch_args+=("$project")
  rm -f "$CODEX_LAUNCH_TEST_ARGS"
  launch_status=0
  DIRENV_LOG_FORMAT='' "$LAUNCH_TEST_TOOL" "${launch_args[@]}" \
    >"$LAUNCH_TEST_ROOT/output" 2>"$LAUNCH_TEST_ROOT/error" || launch_status=$?
  # direnv reports a failed .envrc as status 1, preserving its original status
  # in the diagnostic. The launcher must return direnv's failure unchanged.
  [[ "$launch_status" -eq 1 ]] || fail "$launch_command changed direnv exit status to $launch_status"
  [[ ! -e "$CODEX_LAUNCH_TEST_ARGS" ]] || fail 'CLI ran after .envrc failed'
  for diagnostic in 'fixture setup output' 'fixture required-tool is missing' \
    'exit status 42' "failed to launch project: $project (exit 1)" "verify the project's .envrc"; do
    grep -Fq -- "$diagnostic" "$LAUNCH_TEST_ROOT/error" || {
      cat "$LAUNCH_TEST_ROOT/error" >&2
      fail "missing diagnostic: $diagnostic"
    }
  done
done

# Equivalent physical homes are accepted even when the .envrc uses a symlink.
home_alias="$LAUNCH_TEST_ROOT/home alias"
ln -s "$unit_home" "$home_alias"
write_fixture launch-unit "$home_alias"
approve_fixture
quiet_check "$LAUNCH_TEST_TOOL" vscode-project "$project" >/dev/null
[[ "$(tail -n 1 "$CODEX_LAUNCH_TEST_ENV")" == "$home_alias" ]] || fail 'canonical home alias was rejected or rewritten'
grep -Fxq -- "$unit_home/vscode-user-data" "$CODEX_LAUNCH_TEST_ARGS" || fail 'home alias changed the isolated data directory'

# Inherited identity values must not rescue an incomplete or blocked .envrc.
export CODEX_IDENTITY=launch-unit CODEX_HOME="$unit_home"
write_fixture launch-unit "$other_home"
approve_fixture
expect_rejection "but CODEX_HOME is" "$LAUNCH_TEST_TOOL" vscode-project "$project"
write_fixture launch-unit "$LAUNCH_TEST_ROOT/nonexistent-home"
approve_fixture
expect_rejection "CODEX_HOME does not exist" "$LAUNCH_TEST_TOOL" vscode-project "$project"
printf 'export CODEX_IDENTITY=launch-unit\n' >"$project/.envrc"
approve_fixture
expect_rejection "did not load a Codex identity" "$LAUNCH_TEST_TOOL" vscode-project "$project"
printf 'export CODEX_HOME=%q\n' "$unit_home" >"$project/.envrc"
approve_fixture
expect_rejection "did not load a Codex identity" "$LAUNCH_TEST_TOOL" vscode-project "$project"

write_fixture launch-unit "$unit_home"
approve_fixture
direnv deny "$project" >/dev/null 2>&1
expect_rejection "did not load a Codex identity" "$LAUNCH_TEST_TOOL" vscode-project "$project"
approve_fixture
printf '# changed after approval\n' >>"$project/.envrc"
expect_rejection "is blocked" "$LAUNCH_TEST_TOOL" vscode-project "$project"
mv "$project/.envrc" "$project/.envrc.saved"
expect_rejection "cannot read" "$LAUNCH_TEST_TOOL" vscode-project "$project"
mv "$project/.envrc.saved" "$project/.envrc"

# Validation and execution must use the same clean environment. Otherwise an
# approved conditional .envrc can validate one identity and launch another.
{
  printf 'if [[ -n "${CODEX_IDENTITY:-}${CODEX_HOME:-}" ]]; then\n'
  printf '  export CODEX_IDENTITY=launch-other CODEX_HOME=%q\n' "$other_home"
  printf 'else\n  export CODEX_IDENTITY=launch-unit CODEX_HOME=%q\nfi\n' "$unit_home"
} >"$project/.envrc"
approve_fixture
quiet_check "$LAUNCH_TEST_TOOL" vscode-project "$project" >/dev/null
[[ "$(head -n 1 "$CODEX_LAUNCH_TEST_ENV")" == launch-unit ]] || fail 'execution reused identity state stripped during validation'
[[ "$(tail -n 1 "$CODEX_LAUNCH_TEST_ENV")" == "$unit_home" ]] || fail 'execution home differs from validated home'

# Both public commands evaluate the approved file once and launch its exact env.
write_fixture launch-unit "$unit_home"
cat >>"$project/.envrc" <<'EOF'
printf 'loaded\n' >>"$CODEX_LAUNCH_TEST_LOADS"
export CODEX_LAUNCH_TEST_NONCE="$(wc -l <"$CODEX_LAUNCH_TEST_LOADS" | tr -d '[:space:]')"
EOF
approve_fixture
for launch_command in vscode-project vscode; do
  rm -f "$CODEX_LAUNCH_TEST_LOADS"
  if [[ "$launch_command" == vscode ]]; then
    quiet_check "$LAUNCH_TEST_TOOL" vscode launch-unit "$project" >/dev/null
  else
    quiet_check "$LAUNCH_TEST_TOOL" vscode-project "$project" >/dev/null
  fi
  [[ "$(wc -l <"$CODEX_LAUNCH_TEST_LOADS" | tr -d '[:space:]')" == 1 ]] || fail "$launch_command evaluated .envrc more than once"
  [[ "$(tail -n 1 "$CODEX_LAUNCH_TEST_DETAILS")" == 1 ]] || fail 'CLI did not receive the validated environment'
done

# A project cannot redefine the registry against which its home is checked.
foreign_root="$LAUNCH_TEST_ROOT/foreign identities"
mkdir -p "$foreign_root/launch-unit"
cp "$unit_home/config.toml" "$foreign_root/launch-unit/config.toml"
write_fixture launch-unit "$foreign_root/launch-unit"
printf 'export CODEX_HOMES_ROOT=%q\n' "$foreign_root" >>"$project/.envrc"
approve_fixture
expect_rejection "but CODEX_HOME is" "$LAUNCH_TEST_TOOL" vscode-project "$project"

# The loaded process uses the caller's default home, not its current HOME.
# Exercise this boundary directly so the test never accesses the real .codex.
default_home="$LAUNCH_TEST_ROOT/caller default/.codex"
mkdir -p "$default_home"
cp "$unit_home/config.toml" "$default_home/config.toml"
quiet_check env CODEX_IDENTITY=default CODEX_HOME="$default_home" \
  "$LAUNCH_TEST_TOOL" _vscode-loaded "$project" default \
  "$default_home" "$CODEX_VSCODE_CLI" "$CODEX_VSCODE_EXTENSIONS_DIR" 0 >/dev/null
grep -Fxq -- "$default_home/vscode-user-data" "$CODEX_LAUNCH_TEST_ARGS" || fail 'default identity ignored caller home'
expect_rejection "but CODEX_HOME is" env CODEX_IDENTITY=default CODEX_HOME="$unit_home" \
  "$LAUNCH_TEST_TOOL" _vscode-loaded "$project" default \
  "$default_home" "$CODEX_VSCODE_CLI" "$CODEX_VSCODE_EXTENSIONS_DIR" 0

# Bootstrap and editor selection use caller paths, even if the project changes
# PATH or launcher settings. Unrelated project environment reaches the editor.
alternate_bin="$LAUNCH_TEST_ROOT/alternate bin"
mkdir -p "$alternate_bin"
for shadowed_command in bash code codex-home; do
  printf '#!/bin/sh\nexit 93\n' >"$alternate_bin/$shadowed_command"
  chmod +x "$alternate_bin/$shadowed_command"
done
write_fixture launch-unit "$unit_home"
printf 'PATH_add %q\n' "$alternate_bin" >>"$project/.envrc"
printf 'export CODEX_VSCODE_CLI=%q\n' "$alternate_bin/code" >>"$project/.envrc"
printf 'export CODEX_VSCODE_EXTENSIONS_DIR=%q\n' "$LAUNCH_TEST_ROOT/absent extensions" >>"$project/.envrc"
printf 'export CODEX_VSCODE_DOCK_LABEL=1\nexport CODEX_LAUNCH_TEST_NONCE=project-value\n' >>"$project/.envrc"
approve_fixture
quiet_check "$LAUNCH_TEST_TOOL" vscode-project "$project" >/dev/null
grep -Fxq -- "$CODEX_VSCODE_EXTENSIONS_DIR" "$CODEX_LAUNCH_TEST_ARGS" || fail 'project overrode caller extensions selection'
[[ "$(tail -n 1 "$CODEX_LAUNCH_TEST_DETAILS")" == project-value ]] || fail 'project environment was discarded'

write_fixture launch-unit "$unit_home"
approve_fixture
launch_status=0
CODEX_LAUNCH_TEST_EXIT=37 "$LAUNCH_TEST_TOOL" vscode-project "$project" \
  >/dev/null 2>"$LAUNCH_TEST_ROOT/error" || launch_status=$?
[[ "$launch_status" -eq 37 ]] || fail "CLI exit status was changed to $launch_status"
printf 'Project launch tests passed.\n'
