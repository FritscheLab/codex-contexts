#!/usr/bin/env bash
# Exercise installer locking/publication with temporary bundles and no GUI tools.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || exit 0
INSTALL_TEST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
INSTALL_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-install-test.XXXXXX")"
INSTALL_TEST_ROOT="$(cd "$INSTALL_TEST_ROOT" && pwd -P)"
trap 'rm -rf -- "$INSTALL_TEST_ROOT"' EXIT
fail() { printf 'Install test failure: %s\n' "$*" >&2; exit 1; }
await_file() {
  local attempt=0
  until [[ -e "$1" ]]; do
    attempt=$((attempt + 1))
    [[ "$attempt" -lt 500 ]] || fail "timed out waiting for $1"
    /bin/sleep 0.02
  done
}
inode() { /usr/bin/stat -f '%d:%i' "$1"; }

# Observe an actual contended flock, rather than assuming a scheduling delay
# proves that the second installer waited before checking or building anything.
cat >"$INSTALL_TEST_ROOT/observe-lock.py" <<'PY'
import fcntl
import os
import runpy
import sys

original_flock = fcntl.flock

def observe_flock(fd, operation):
    try:
        original_flock(fd, operation | fcntl.LOCK_NB)
    except BlockingIOError:
        with open(os.environ["INSTALL_TEST_BLOCKED"], "w"):
            pass
        original_flock(fd, operation)

fcntl.flock = observe_flock
sys.argv = sys.argv[1:]
runpy.run_path(sys.argv[0], run_name="__main__")
PY

run_install() (
  local label="$1" apps="$2" services="$3" mode="${4:-normal}"
  export CODEX_MACOS_APP_DIR="$apps" CODEX_MACOS_SERVICES_DIR="$services"
  export CODEX_MACOS_SKIP_REGISTER=1
  export INSTALL_TEST_BLOCKED="$INSTALL_TEST_ROOT/$label.blocked"
  osacompile() {
    mkdir -p "$2/Contents/Resources"
    /usr/bin/plutil -create xml1 "$2/Contents/Info.plist"
    printf '%s\n' "$label" >"$2/build-id"
    touch "$INSTALL_TEST_ROOT/$label.building"
    if [[ "$mode" == hold ]]; then
      await_file "$INSTALL_TEST_ROOT/$label.release"
    elif [[ "$mode" == fail-build ]]; then
      return 72
    fi
  }
  function /usr/bin/codesign { return 0; }
  cp() {
    command cp "$@" || return "$?"
    if [[ "$1" == -R && "$2" == "$INSTALL_TEST_REPO/macos/OpenInCodexProject.workflow" ]]; then
      printf '%s\n' "$label" >"$3/build-id"
    fi
  }
  python3() {
    if [[ "${1:-}" == -I && "${2:-}" == */macos_bundles.py ]]; then
      if [[ "${3:-}" == lock && "$mode" == observe ]]; then
        shift
        command python3 -I "$INSTALL_TEST_ROOT/observe-lock.py" "$@"
        return "$?"
      fi
      if [[ "${3:-}" == rename && "${4:-}" == "$BUILT_WORKFLOW" && "${5:-}" == "$WORKFLOW_PATH" ]]; then
        case "$mode" in
          fail-workflow) return 71 ;;
          foreign-workflow)
            mkdir "$WORKFLOW_PATH"
            printf 'unrelated workflow\n' >"$WORKFLOW_PATH/retained"
            ;;
          foreign-app)
            command mv "$APP_PATH" "$INSTALL_TEST_ROOT/$label.published-app"
            mkdir "$APP_PATH"
            printf 'unrelated application\n' >"$APP_PATH/retained"
            return 71 ;;
        esac
      fi
      if [[ "${3:-}" == rename && "${4:-}" == "$BUILT_APP" && "${5:-}" == "$APP_PATH" && "$mode" == signal-* ]]; then
        command python3 "$@" || return "$?"
        /bin/sh -c 'kill -"$1" "$PPID"' sh "${mode#signal-}"
        return 0
      fi
    fi
    command python3 "$@"
  }
  # Empty initial values let the Python wrapper inspect the early lock call.
  BUILT_APP="" BUILT_WORKFLOW="" APP_PATH="" WORKFLOW_PATH=""
  set --
  source "$INSTALL_TEST_REPO/bin/install-macos-open-with"
)

wait_success() {
  local pid="$1" label="$2"
  if ! wait "$pid"; then
    cat "$INSTALL_TEST_ROOT/$label.output" >&2
    fail "$label installation failed"
  fi
}
assert_install() {
  local apps="$1" services="$2" label="$3" command
  [[ "$(cat "$apps/Codex Project.app/build-id")" == "$label" ]] || fail 'wrong final app'
  [[ "$(cat "$services/Open in Codex Project.workflow/build-id")" == "$label" ]] || fail 'wrong final workflow'
  [[ ! -e "$apps/Codex Project.app/Codex Project.app" &&
    ! -e "$services/Open in Codex Project.workflow/Open in Codex Project.workflow" ]] || fail 'nested published bundles'
  command="$(/usr/bin/plutil -extract actions.0.action.ActionParameters.COMMAND_STRING raw \
    "$services/Open in Codex Project.workflow/Contents/Resources/document.wflow")"
  printf -v expected '[[ "$#" -gt 0 ]] || exit 0\nexec /usr/bin/open -a %q -- "$@"' "$apps/Codex Project.app"
  [[ "$command" == "$expected" ]] || fail 'workflow points to the wrong app'
}
overlap() {
  local name="$1" first_apps="$2" first_services="$3" second_apps="$4" second_services="$5"
  local first="$name-first" second="$name-second" first_pid second_pid
  run_install "$first" "$first_apps" "$first_services" hold >"$INSTALL_TEST_ROOT/$first.output" 2>&1 &
  first_pid=$!
  await_file "$INSTALL_TEST_ROOT/$first.building"
  run_install "$second" "$second_apps" "$second_services" observe >"$INSTALL_TEST_ROOT/$second.output" 2>&1 &
  second_pid=$!
  await_file "$INSTALL_TEST_ROOT/$second.blocked"
  [[ ! -e "$INSTALL_TEST_ROOT/$second.building" ]] || fail 'second installer built before acquiring locks'
  touch "$INSTALL_TEST_ROOT/$first.release"
  wait_success "$first_pid" "$first"
  wait_success "$second_pid" "$second"
  assert_install "$second_apps" "$second_services" "$second"
}

apps="$INSTALL_TEST_ROOT/apps"
services="$INSTALL_TEST_ROOT/services"
overlap fresh "$apps" "$services" "$apps" "$services"

# Help and unknown arguments must be handled before touching either bundle.
check_arguments() (
  export CODEX_MACOS_APP_DIR="$apps" CODEX_MACOS_SERVICES_DIR="$services"
  export CODEX_MACOS_TRASH_DIR="$INSTALL_TEST_ROOT/trash" CODEX_MACOS_SKIP_REGISTER=1
  local script="$1" old_app old_workflow
  old_app="$(inode "$apps/Codex Project.app")"
  old_workflow="$(inode "$services/Open in Codex Project.workflow")"
  for flag in -h --help; do
    "$INSTALL_TEST_REPO/bin/$script" "$flag" >"$INSTALL_TEST_ROOT/help-output" ||
      fail "$script rejected $flag"
    grep -Fq "Usage: $script" "$INSTALL_TEST_ROOT/help-output" || fail "$script did not show help"
  done
  if "$INSTALL_TEST_REPO/bin/$script" --unknown >"$INSTALL_TEST_ROOT/help-output" 2>&1; then
    fail "$script accepted an unknown option"
  fi
  grep -Fq 'unexpected arguments' "$INSTALL_TEST_ROOT/help-output" || fail 'missing argument diagnostic'
  [[ "$(inode "$apps/Codex Project.app")" == "$old_app" &&
    "$(inode "$services/Open in Codex Project.workflow")" == "$old_workflow" &&
    ! -e "$CODEX_MACOS_TRASH_DIR" ]] || fail "$script changed the installations while handling arguments"
)
check_arguments install-macos-open-with
check_arguments uninstall-macos-open-with

app_lock_inode="$(inode "$apps/.codex-contexts-install.lock")"
workflow_lock_inode="$(inode "$services/.codex-contexts-install.lock")"
overlap reinstall "$apps" "$services" "$apps" "$services"
[[ "$(inode "$apps/.codex-contexts-install.lock")" == "$app_lock_inode" &&
  "$(inode "$services/.codex-contexts-install.lock")" == "$workflow_lock_inode" ]] || fail 'replaced stable lock inodes'
overlap shared-app "$apps" "$services" "$apps" "$INSTALL_TEST_ROOT/other-services"
overlap shared-workflow "$apps" "$services" "$INSTALL_TEST_ROOT/other-apps" "$services"
overlap reversed "$INSTALL_TEST_ROOT/left" "$INSTALL_TEST_ROOT/right" \
  "$INSTALL_TEST_ROOT/right" "$INSTALL_TEST_ROOT/left"
overlap same-directory "$INSTALL_TEST_ROOT/combined" "$INSTALL_TEST_ROOT/combined" \
  "$INSTALL_TEST_ROOT/combined" "$INSTALL_TEST_ROOT/combined"

# Failed publication and signals after app publication restore exact old inodes.
for mode in fail-build fail-workflow signal-HUP signal-INT signal-TERM; do
  old_app="$(inode "$apps/Codex Project.app")"
  old_workflow="$(inode "$services/Open in Codex Project.workflow")"
  status=0
  if [[ "$mode" == signal-* ]]; then
    # Bash 3.2 background jobs inherit SIGINT ignored. Exercise explicit signal
    # traps in a foreground subshell; build failures still exercise errexit.
    run_install "$mode" "$apps" "$services" "$mode" >"$INSTALL_TEST_ROOT/$mode.output" 2>&1 || status=$?
  else
    run_install "$mode" "$apps" "$services" "$mode" >"$INSTALL_TEST_ROOT/$mode.output" 2>&1 &
    pid=$!
    wait "$pid" || status=$?
  fi
  [[ "$status" != 0 ]] || fail "accepted $mode"
  [[ "$(inode "$apps/Codex Project.app")" == "$old_app" &&
    "$(inode "$services/Open in Codex Project.workflow")" == "$old_workflow" ]] || fail "$mode did not restore exact prior bundles"
  run_install "$mode-retry" "$apps" "$services" >"$INSTALL_TEST_ROOT/$mode-retry.output" 2>&1 &
  wait_success "$!" "$mode-retry"
done

# A later unrelated destination is preserved, with the obstructed prior bundle
# retained in the reported recovery directory; the other component is restored.
for mode in foreign-workflow foreign-app; do
  conflict_apps="$INSTALL_TEST_ROOT/$mode-apps"
  conflict_services="$INSTALL_TEST_ROOT/$mode-services"
  run_install "$mode-before" "$conflict_apps" "$conflict_services" >"$INSTALL_TEST_ROOT/$mode-before.output" 2>&1 &
  wait_success "$!" "$mode-before"
  old_app="$(inode "$conflict_apps/Codex Project.app")"
  old_workflow="$(inode "$conflict_services/Open in Codex Project.workflow")"
  run_install "$mode" "$conflict_apps" "$conflict_services" "$mode" >"$INSTALL_TEST_ROOT/$mode.output" 2>&1 &
  status=0
  wait "$!" || status=$?
  [[ "$status" != 0 ]] || fail "accepted $mode"
  grep -Fq 'recover previous components from' "$INSTALL_TEST_ROOT/$mode.output" || fail 'missing recovery guidance'
  if [[ "$mode" == foreign-workflow ]]; then
    [[ -f "$conflict_services/Open in Codex Project.workflow/retained" &&
      "$(inode "$conflict_apps/Codex Project.app")" == "$old_app" ]] || fail 'lost foreign workflow or original app'
    backups=("$conflict_services"/.codex-project-install.*/previous.workflow)
    [[ "${#backups[@]}" == 1 && "$(inode "${backups[0]}")" == "$old_workflow" ]] || fail 'lost obstructed original workflow'
  else
    [[ -f "$conflict_apps/Codex Project.app/retained" &&
      "$(inode "$conflict_services/Open in Codex Project.workflow")" == "$old_workflow" ]] || fail 'lost foreign app or original workflow'
    backups=("$conflict_apps"/.codex-project-install.*/previous.app)
    [[ "${#backups[@]}" == 1 && "$(inode "${backups[0]}")" == "$old_app" ]] || fail 'lost obstructed original app'
  fi
done

for kind in symlink fifo hardlink writable unsafe-parent; do
  unsafe_apps="$INSTALL_TEST_ROOT/unsafe-$kind"
  mkdir -p "$unsafe_apps"
  lock="$unsafe_apps/.codex-contexts-install.lock"
  printf 'keep lock target\n' >"$INSTALL_TEST_ROOT/$kind-target"
  case "$kind" in
    symlink) ln -s "$INSTALL_TEST_ROOT/$kind-target" "$lock" ;;
    fifo) mkfifo "$lock" ;;
    hardlink) ln "$INSTALL_TEST_ROOT/$kind-target" "$lock" ;;
    writable) touch "$lock"; chmod 666 "$lock" ;;
    unsafe-parent) chmod 770 "$unsafe_apps" ;;
  esac
  run_install "unsafe-$kind" "$unsafe_apps" "$INSTALL_TEST_ROOT/unsafe-services" >"$INSTALL_TEST_ROOT/unsafe-$kind.output" 2>&1 &
  status=0
  wait "$!" || status=$?
  [[ "$status" != 0 && ! -e "$INSTALL_TEST_ROOT/unsafe-$kind.building" ]] || fail "accepted unsafe $kind lock"
  [[ "$(cat "$INSTALL_TEST_ROOT/$kind-target")" == 'keep lock target' ]] || fail 'changed lock target'
done
printf 'Mac installer tests passed.\n'
