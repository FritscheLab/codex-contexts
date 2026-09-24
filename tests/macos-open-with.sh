#!/usr/bin/env bash
# Offline Finder app failure tests; all apps stay in a temporary directory.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || exit 0
OPEN_WITH_TEST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$OPEN_WITH_TEST_REPO/tests/common.sh"
OPEN_WITH_TEST_TOOL="$(resolve_codex_home_tool "$OPEN_WITH_TEST_REPO/bin")"
OPEN_WITH_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-open-with-test.XXXXXX")"
OPEN_WITH_TEST_ROOT="$(cd "$OPEN_WITH_TEST_ROOT" && pwd -P)"
trap 'rm -rf -- "$OPEN_WITH_TEST_ROOT"' EXIT
source "$OPEN_WITH_TEST_TOOL"
CODEX_MACOS_SKIP_REGISTER=0
OPEN_WITH_TEST_FAILURE=""

fail() { printf 'Finder app test failure: %s\n' "$*" >&2; exit 1; }
macos_vscode_open_with_path() {
  printf '%s/Applications/VS Code - %s.app\n' "$OPEN_WITH_TEST_ROOT" "$1"
}
# Bash also resolves absolute command names as functions. Intercept every
# LaunchServices call so these tests cannot change the user's registration.
function /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister {
  return 0
}
# Bundle publication does not need a working UI script. Compile a minimal app
# with real macOS tools, keeping the build independent of UI terminology access.
printf 'on run\n  return\nend run\n' >"$OPEN_WITH_TEST_ROOT/fixture.applescript"
osacompile() {
  command osacompile "$1" "$2" "$OPEN_WITH_TEST_ROOT/fixture.applescript"
}
cp() {
  case "$OPEN_WITH_TEST_FAILURE:$1" in
    config-copy:*/config/umgpt-models.toml|helper-copy:"$OPEN_WITH_TEST_TOOL") return 73 ;;
  esac
  command cp "$@"
}
function /usr/libexec/PlistBuddy {
  if [[ "$OPEN_WITH_TEST_FAILURE" == plist && "$2" == 'Add :CFBundleIdentifier '* ]]; then
    return 74
  fi
  command /usr/libexec/PlistBuddy "$@"
}
mv() {
  if [[ "$2" == "$app" ]]; then
    case "$OPEN_WITH_TEST_FAILURE:$1" in
      install:*/.vscode-open-with.*/VS\ Code\ -\ finder-unit.app|restore:*/.vscode-open-with.*/VS\ Code\ -\ finder-unit.app|restore:*/previous.app)
        return 75 ;;
    esac
  fi
  command mv "$@" || return "$?"
  if [[ "$OPEN_WITH_TEST_FAILURE" == signal && "$2" == */previous.app ]]; then
    # This child sends TERM to the helper's subshell, including on Bash 3.2.
    /bin/sh -c 'kill -TERM "$PPID"'
  fi
}

app="$(macos_vscode_open_with_path finder-unit)"
identity_home="$OPEN_WITH_TEST_ROOT/identity"
error_file="$OPEN_WITH_TEST_ROOT/error"
if ! ensure_macos_vscode_open_with finder-unit "$identity_home" 2>"$error_file"; then
  cat "$error_file" >&2
  fail 'initial installation failed'
fi
cmp -s "$OPEN_WITH_TEST_REPO/config/umgpt-models.toml" "$app/Contents/config/umgpt-models.toml" ||
  fail 'successful installation lost its model defaults'
[[ -x "$app/Contents/Resources/codex-home" ]] || fail 'installed helper is not executable'
printf 'retain this exact app\n' >"$app/retained-file"
app_inode="$(stat -f %i "$app")"
ensure_macos_vscode_open_with finder-unit "$identity_home"
[[ "$(stat -f %i "$app")" == "$app_inode" ]] || fail 'unchanged app was rebuilt'

assert_previous_app() {
  [[ -d "$app" && "$(stat -f %i "$app")" == "$app_inode" && -f "$app/retained-file" ]] ||
    fail 'failure lost or replaced the previous app'
}
expect_failure() {
  local expected_status="${1:-1}" status=0
  # Force a refresh while preserving the ownership marker's expected format.
  printf 'codex-contexts-vscode-open-with-v1\noutdated\n' >"$app/Contents/Resources/codex-contexts-open-with"
  # The normal caller handles failure with ||. An if condition likewise disables
  # errexit inside the function, exercising its explicit error handling.
  if ensure_macos_vscode_open_with finder-unit "$identity_home" 2>"$error_file"; then
    fail "ignored $OPEN_WITH_TEST_FAILURE failure"
  else
    status=$?
  fi
  [[ "$status" == "$expected_status" ]] || fail "unexpected $OPEN_WITH_TEST_FAILURE exit status: $status"
}

for OPEN_WITH_TEST_FAILURE in config-copy helper-copy plist install; do
  expect_failure
  assert_previous_app
  [[ -z "$(find "$OPEN_WITH_TEST_ROOT/Applications" -maxdepth 1 -name '.vscode-open-with.*' -print)" ]] ||
    fail 'successful recovery left a staging directory'
done

OPEN_WITH_TEST_FAILURE=signal
expect_failure 143
assert_previous_app

OPEN_WITH_TEST_FAILURE=restore
expect_failure
[[ ! -e "$app" ]] || fail 'fixture did not reach the failed restoration path'
backups=("$OPEN_WITH_TEST_ROOT/Applications"/.vscode-open-with.*/previous.app)
[[ "${#backups[@]}" == 1 && -f "${backups[0]}/retained-file" ]] || fail 'failed rollback deleted the previous app'
grep -Fq "${backups[0]}" "$error_file" || fail 'failed rollback did not report its recovery path'
command mv "${backups[0]}" "$app"
assert_previous_app
printf 'Mac Finder app tests passed.\n'
