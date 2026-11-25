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
  printf '%s\n' "$*" >>"$OPEN_WITH_TEST_ROOT/registration-calls"
  return 0
}
# Bundle publication does not need a working UI script. Compile a minimal app
# with real macOS tools, keeping the build independent of UI terminology access.
printf 'on run\n  return\nend run\n' >"$OPEN_WITH_TEST_ROOT/fixture.applescript"
osacompile() {
  : >"$OPEN_WITH_TEST_ROOT/build-called"
  command osacompile "$1" "$2" "$OPEN_WITH_TEST_ROOT/fixture.applescript"
}
cp() {
  : >"$OPEN_WITH_TEST_ROOT/copy-called"
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
python3() {
  if [[ "${1:-}" == -I && "${2:-}" == */macos_bundles.py && "${3:-}" == rename ]]; then
    if [[ "$5" == "$app" ]]; then
      case "$OPEN_WITH_TEST_FAILURE:$4" in
        install:*/.vscode-open-with.*/VS\ Code\ -\ finder-unit.app|restore:*/.vscode-open-with.*/VS\ Code\ -\ finder-unit.app|restore:*/previous.app)
          return 75 ;;
      esac
    fi
    command python3 "$@" || return "$?"
    if [[ "$OPEN_WITH_TEST_FAILURE" == signal && "$5" == */previous.app ]]; then
      # Signal after the atomic rename, before the caller can record success.
      /bin/sh -c 'kill -TERM "$PPID"'
    fi
    return 0
  fi
  command python3 "$@"
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
"$app/Contents/Resources/codex-home" help >/dev/null || fail 'bundled helper cannot load its support libraries'
printf 'retain this exact app\n' >"$app/retained-file"
app_inode="$(stat -f %i "$app")"
finder_lock="$OPEN_WITH_TEST_ROOT/Applications/.codex-contexts-vscode-finder-unit.lock"
finder_lock_id="$(/usr/bin/stat -f '%d:%i' "$finder_lock")"
ensure_macos_vscode_open_with finder-unit "$identity_home"
[[ "$(stat -f %i "$app")" == "$app_inode" ]] || fail 'unchanged app was rebuilt'

assert_lock_released() {
  command python3 - "$OPEN_WITH_TEST_ROOT/Applications/.codex-contexts-vscode-$1.lock" <<'PY'
import fcntl
import sys

with open(sys.argv[1], 'a') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
PY
}

# Ownership checks must run before compilation, copying, or registration. Keep
# content, permissions, inodes, and symlink targets in the refusal snapshot.
snapshot_ownership_fixture() {
  python3 - "$app" "$OPEN_WITH_TEST_ROOT/link-targets" <<'PY'
import hashlib
import json
import os
import stat
import sys

def inspect(path):
    info = os.lstat(path)
    record = [path, info.st_ino, info.st_mode, info.st_mtime_ns]
    if stat.S_ISLNK(info.st_mode):
        record.append(os.readlink(path))
    elif stat.S_ISREG(info.st_mode):
        with open(path, 'rb') as source:
            record.append(hashlib.sha256(source.read()).hexdigest())
    print(json.dumps(record))
    if stat.S_ISDIR(info.st_mode):
        for name in sorted(os.listdir(path)):
            inspect(os.path.join(path, name))

for path in sys.argv[1:]:
    inspect(path)
PY
}
assert_ownership_refusal() {
  snapshot_ownership_fixture >"$OPEN_WITH_TEST_ROOT/ownership-before"
  command rm -f "$OPEN_WITH_TEST_ROOT/registration-calls" \
    "$OPEN_WITH_TEST_ROOT/build-called" "$OPEN_WITH_TEST_ROOT/copy-called"
  if ensure_macos_vscode_open_with finder-unit "$identity_home" 2>"$error_file"; then
    fail "accepted unsafe ownership: $1"
  fi
  snapshot_ownership_fixture >"$OPEN_WITH_TEST_ROOT/ownership-after"
  cmp -s "$OPEN_WITH_TEST_ROOT/ownership-before" "$OPEN_WITH_TEST_ROOT/ownership-after" ||
    fail "changed an unsafe app or symlink target: $1"
  [[ ! -e "$OPEN_WITH_TEST_ROOT/registration-calls" &&
    ! -e "$OPEN_WITH_TEST_ROOT/build-called" && ! -e "$OPEN_WITH_TEST_ROOT/copy-called" ]] ||
    fail "started replacement before checking ownership: $1"
  grep -Fq 'refusing to replace an unowned Finder app' "$error_file" ||
    fail "missing ownership refusal diagnostic: $1"
  [[ -z "$(find "$OPEN_WITH_TEST_ROOT/Applications" -maxdepth 1 -name '.vscode-open-with.*' -print)" ]] ||
    fail "staged a replacement for unsafe ownership: $1"
}
mkdir -p "$OPEN_WITH_TEST_ROOT/link-targets" "$identity_home/vscode-editor/VS Code - finder-unit.app"
ownership_marker="$app/Contents/Resources/codex-contexts-open-with"
command cp "$ownership_marker" "$OPEN_WITH_TEST_ROOT/owned-marker"
for invalid_marker in '' 'unrelated-marker' $'codex-contexts-vscode-open-with-v1\nother-identity\noutdated'; do
  printf '%s\n' "$invalid_marker" >"$ownership_marker"
  assert_ownership_refusal 'empty, invalid, or mismatched marker'
done
command mv "$ownership_marker" "$OPEN_WITH_TEST_ROOT/invalid-marker"
assert_ownership_refusal 'missing marker'
command cp "$OPEN_WITH_TEST_ROOT/owned-marker" "$ownership_marker"

for ownership_path in Contents/Resources/codex-contexts-open-with Contents/Info.plist \
  Contents/Resources/identity Contents/Resources/codex-home Contents/Resources Contents; do
  link_target="$OPEN_WITH_TEST_ROOT/link-targets/$(basename "$ownership_path")"
  command mv "$app/$ownership_path" "$link_target"
  ln -s "$link_target" "$app/$ownership_path"
  assert_ownership_refusal "symlinked $ownership_path"
  unlink "$app/$ownership_path"
  command mv "$link_target" "$app/$ownership_path"
done
command cp "$app/Contents/Info.plist" "$OPEN_WITH_TEST_ROOT/owned-info.plist"
command /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier org.example.unrelated' "$app/Contents/Info.plist"
assert_ownership_refusal 'unrelated bundle identifier'
command cp "$OPEN_WITH_TEST_ROOT/owned-info.plist" "$app/Contents/Info.plist"
printf 'other-identity\n' >"$app/Contents/Resources/identity"
assert_ownership_refusal 'mismatched bundled identity'
printf 'finder-unit\n' >"$app/Contents/Resources/identity"

assert_previous_app() {
  [[ -d "$app" && "$(stat -f %i "$app")" == "$app_inode" && -f "$app/retained-file" ]] ||
    fail 'failure lost or replaced the previous app'
}
expect_failure() {
  local expected_status="${1:-1}" status=0
  # Force a refresh while preserving the ownership marker's expected format.
  printf 'codex-contexts-vscode-open-with-v1\nfinder-unit\noutdated\n' >"$app/Contents/Resources/codex-contexts-open-with"
  # The normal caller handles failure with ||. An if condition likewise disables
  # errexit inside the function, exercising its explicit error handling.
  if ensure_macos_vscode_open_with finder-unit "$identity_home" 2>"$error_file"; then
    fail "ignored $OPEN_WITH_TEST_FAILURE failure"
  else
    status=$?
  fi
  [[ "$status" == "$expected_status" ]] || fail "unexpected $OPEN_WITH_TEST_FAILURE exit status: $status"
  [[ "$(/usr/bin/stat -f '%d:%i' "$finder_lock")" == "$finder_lock_id" ]] || fail 'failure replaced the stable lock'
  assert_lock_released finder-unit
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
grep -Fq "$(dirname "${backups[0]}")" "$error_file" || fail 'failed rollback did not report its recovery path'
command mv "${backups[0]}" "$app"
assert_previous_app

# Old metadata is refreshable once the ownership and identity records match.
OPEN_WITH_TEST_FAILURE=""
find "$OPEN_WITH_TEST_ROOT/Applications" -maxdepth 1 -name '.vscode-open-with.*' -print \
  >"$OPEN_WITH_TEST_ROOT/staging-before-refresh"
ensure_macos_vscode_open_with finder-unit "$identity_home"
[[ "$(stat -f %i "$app")" != "$app_inode" ]] || fail 'owned stale metadata did not refresh'
[[ "$(sed -n '2p' "$app/Contents/Resources/codex-contexts-open-with")" == finder-unit ]] ||
  fail 'refresh lost the marker identity'
[[ -x "$app/Contents/Resources/codex-home" ]] || fail 'refresh lost the bundled helper'
find "$OPEN_WITH_TEST_ROOT/Applications" -maxdepth 1 -name '.vscode-open-with.*' -print \
  >"$OPEN_WITH_TEST_ROOT/staging-after-refresh"
cmp -s "$OPEN_WITH_TEST_ROOT/staging-before-refresh" "$OPEN_WITH_TEST_ROOT/staging-after-refresh" ||
  fail 'successful refresh left a staging directory'

# A support-library update must refresh the installed artifact, even when the
# small launcher and AppleScript are unchanged.
(
  command cp -R "$CODEX_CONTEXTS_LIB" "$OPEN_WITH_TEST_ROOT/support-copy"
  CODEX_CONTEXTS_LIB="$OPEN_WITH_TEST_ROOT/support-copy"
  ensure_macos_vscode_open_with library-refresh "$identity_home"
  library_app="$(macos_vscode_open_with_path library-refresh)"
  library_inode="$(stat -f %i "$library_app")"
  printf '\n# Synthetic support-library update.\n' >>"$CODEX_CONTEXTS_LIB/macos.sh"
  ensure_macos_vscode_open_with library-refresh "$identity_home"
  [[ "$(stat -f %i "$library_app")" != "$library_inode" ]] || fail 'support-library change did not refresh the handler'
  cmp -s "$CODEX_CONTEXTS_LIB/macos.sh" "$library_app/Contents/Resources/libexec/macos.sh" ||
    fail 'handler did not bundle the updated support library'
)

await_file() {
  local attempt=0
  until [[ -e "$1" ]]; do
    attempt=$((attempt + 1))
    [[ "$attempt" -lt 500 ]] || fail "timed out waiting for $1"
    /bin/sleep 0.02
  done
}
# Observe actual lock contention instead of inferring serialization from timing.
cat >"$OPEN_WITH_TEST_ROOT/observe-lock.py" <<'PY'
import fcntl
import os
import runpy
import sys

original_flock = fcntl.flock

def observe_flock(fd, operation):
    try:
        original_flock(fd, operation | fcntl.LOCK_NB)
    except BlockingIOError:
        with open(os.environ['FINDER_TEST_BLOCKED'], 'w'):
            pass
        original_flock(fd, operation)

fcntl.flock = observe_flock
sys.argv = sys.argv[1:]
runpy.run_path(sys.argv[0], run_name="__main__")
PY
run_handler() (
  local identity="$1" label="$2" mode="${3:-normal}"
  export FINDER_TEST_BLOCKED="$OPEN_WITH_TEST_ROOT/$label.blocked"
  osacompile() {
    mkdir -p "$2/Contents/Resources"
    /usr/bin/plutil -create xml1 "$2/Contents/Info.plist"
    printf '%s\n' "$label" >"$2/build-label"
    touch "$OPEN_WITH_TEST_ROOT/$label.building"
    [[ "$mode" != hold ]] || await_file "$OPEN_WITH_TEST_ROOT/$label.release"
  }
  function /usr/bin/codesign { return 0; }
  python3() {
    if [[ "${1:-}" == -I && "${2:-}" == */macos_bundles.py ]]; then
      if [[ "${3:-}" == lock && "$mode" == observe ]]; then
        shift
        command python3 -I "$OPEN_WITH_TEST_ROOT/observe-lock.py" "$@"
        return "$?"
      fi
      if [[ "${3:-}" == rename && "$4" == "$candidate" && "$5" == "$app" ]]; then
        case "$mode" in
          late-empty) mkdir "$app" ;;
          late-symlink) ln -s "$OPEN_WITH_TEST_ROOT/late-target" "$app" ;;
        esac
        if [[ "$mode" == late-* ]]; then
          /usr/bin/stat -f '%d:%i' "$app" >"$OPEN_WITH_TEST_ROOT/$label.intruder-id"
        elif [[ "$mode" == signal-published ]]; then
          command python3 "$@" || return "$?"
          /bin/sh -c 'kill -TERM "$PPID"'
          return 0
        fi
      fi
    fi
    command python3 "$@"
  }
  ensure_macos_vscode_open_with "$identity" "$OPEN_WITH_TEST_ROOT/identity-$identity"
)

for phase in fresh refresh; do
  race_app="$(macos_vscode_open_with_path concurrent)"
  if [[ "$phase" == refresh ]]; then
    printf 'codex-contexts-vscode-open-with-v1\nconcurrent\noutdated\n' \
      >"$race_app/Contents/Resources/codex-contexts-open-with"
  fi
  run_handler concurrent "$phase-first" hold >"$OPEN_WITH_TEST_ROOT/$phase-first.output" 2>&1 &
  first_pid=$!
  await_file "$OPEN_WITH_TEST_ROOT/$phase-first.building"
  run_handler concurrent "$phase-second" observe >"$OPEN_WITH_TEST_ROOT/$phase-second.output" 2>&1 &
  second_pid=$!
  await_file "$OPEN_WITH_TEST_ROOT/$phase-second.blocked"
  [[ ! -e "$OPEN_WITH_TEST_ROOT/$phase-second.building" ]] || fail 'contending handler built before locking'
  touch "$OPEN_WITH_TEST_ROOT/$phase-first.release"
  wait "$first_pid" || { cat "$OPEN_WITH_TEST_ROOT/$phase-first.output" >&2; fail 'first concurrent handler failed'; }
  wait "$second_pid" || { cat "$OPEN_WITH_TEST_ROOT/$phase-second.output" >&2; fail 'second concurrent handler failed'; }
  [[ "$(cat "$race_app/build-label")" == "$phase-first" &&
    ! -e "$race_app/VS Code - concurrent.app" ]] || fail 'concurrent publication nested or replaced an unchanged app'
  current_lock_id="$(/usr/bin/stat -f '%d:%i' "$OPEN_WITH_TEST_ROOT/Applications/.codex-contexts-vscode-concurrent.lock")"
  if [[ "$phase" == fresh ]]; then race_lock_id="$current_lock_id"; fi
  [[ "$current_lock_id" == "$race_lock_id" ]] || fail 'replaced the stable handler lock'
  assert_lock_released concurrent
done

# A later unrelated destination must survive failed publication and rollback.
mkdir "$OPEN_WITH_TEST_ROOT/late-target"
printf 'retain target\n' >"$OPEN_WITH_TEST_ROOT/late-target/retained"
for mode in late-empty late-symlink signal-published; do
  run_handler "$mode" "$mode-before" >"$OPEN_WITH_TEST_ROOT/$mode-before.output" 2>&1
  late_app="$(macos_vscode_open_with_path "$mode")"
  old_id="$(/usr/bin/stat -f '%d:%i' "$late_app")"
  printf 'codex-contexts-vscode-open-with-v1\n%s\noutdated\n' "$mode" \
    >"$late_app/Contents/Resources/codex-contexts-open-with"
  command rm -f "$OPEN_WITH_TEST_ROOT/registration-calls"
  status=0
  run_handler "$mode" "$mode" "$mode" >"$OPEN_WITH_TEST_ROOT/$mode.output" 2>&1 || status=$?
  [[ "$status" != 0 ]] || fail "accepted $mode during publication"
  assert_lock_released "$mode"
  [[ ! -e "$OPEN_WITH_TEST_ROOT/registration-calls" ]] || fail 'registered after failed publication'
  if [[ "$mode" == signal-published ]]; then
    [[ "$status" == 143 && "$(/usr/bin/stat -f '%d:%i' "$late_app")" == "$old_id" ]] ||
      fail 'signal after publication did not restore the exact old app'
  else
    [[ "$(/usr/bin/stat -f '%d:%i' "$late_app")" == "$(cat "$OPEN_WITH_TEST_ROOT/$mode.intruder-id")" ]] ||
      fail 'replaced the later unrelated destination'
    [[ "$(cat "$OPEN_WITH_TEST_ROOT/late-target/retained")" == 'retain target' ]] || fail 'changed the symlink target'
    backups=("$OPEN_WITH_TEST_ROOT/Applications"/.vscode-open-with.*/previous.app)
    found_old=0
    for backup in "${backups[@]}"; do
      [[ "$(/usr/bin/stat -f '%d:%i' "$backup")" != "$old_id" ]] || found_old=1
    done
    [[ "$found_old" == 1 ]] || fail 'lost the obstructed original app'
    grep -Fq 'recovery incomplete' "$OPEN_WITH_TEST_ROOT/$mode.output" || fail 'missing recovery guidance'
  fi
done

for kind in symlink fifo hardlink writable unsafe-parent; do
  unsafe_dir="$OPEN_WITH_TEST_ROOT/unsafe-$kind"
  mkdir "$unsafe_dir"
  unsafe_lock="$unsafe_dir/.codex-contexts-vscode-lock-unit.lock"
  printf 'retain lock target\n' >"$OPEN_WITH_TEST_ROOT/$kind-target"
  case "$kind" in
    symlink) ln -s "$OPEN_WITH_TEST_ROOT/$kind-target" "$unsafe_lock" ;;
    fifo) mkfifo "$unsafe_lock" ;;
    hardlink) ln "$OPEN_WITH_TEST_ROOT/$kind-target" "$unsafe_lock" ;;
    writable) touch "$unsafe_lock"; chmod 666 "$unsafe_lock" ;;
    unsafe-parent) chmod 770 "$unsafe_dir" ;;
  esac
  if (
    macos_vscode_open_with_path() { printf '%s/VS Code - %s.app\n' "$unsafe_dir" "$1"; }
    run_handler lock-unit "unsafe-$kind"
  ) >"$OPEN_WITH_TEST_ROOT/unsafe-$kind.output" 2>&1; then
    fail "accepted unsafe $kind lock"
  fi
  [[ ! -e "$OPEN_WITH_TEST_ROOT/unsafe-$kind.building" ]] || fail 'built before rejecting an unsafe lock'
  [[ "$(cat "$OPEN_WITH_TEST_ROOT/$kind-target")" == 'retain lock target' ]] || fail 'changed an unsafe lock target'
done
printf 'Mac Finder app tests passed.\n'
