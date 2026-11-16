#!/usr/bin/env bash
# Removal commands must wait for the same locks as bundle writers, then recheck.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || exit 0
MUTATION_TEST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MUTATION_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-mutation-test.XXXXXX")"
MUTATION_TEST_ROOT="$(cd "$MUTATION_TEST_ROOT" && pwd -P)"
CODEX_CONTEXTS_LIB="$MUTATION_TEST_REPO/libexec"
source "$CODEX_CONTEXTS_LIB/macos.sh"
fail() { printf 'Mutation test failure: %s\n' "$*" >&2; exit 1; }
die() { fail "$@"; }
cleanup_test() {
  local child
  for child in $(jobs -pr); do kill "$child" 2>/dev/null || true; done
  wait 2>/dev/null || true
  rm -rf -- "$MUTATION_TEST_ROOT"
}
trap cleanup_test EXIT
await_file() {
  local attempt=0
  until [[ -e "$1" ]]; do
    attempt=$((attempt + 1))
    [[ "$attempt" -lt 500 ]] || fail "timed out waiting for $1"
    /bin/sleep 0.02
  done
}
fixture_app() {
  mkdir -p "$1/Contents/Resources"
  /usr/bin/plutil -create xml1 "$1/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleIdentifier -string "$2" "$1/Contents/Info.plist"
  printf '#!/bin/bash\n' >"$1/Contents/Resources/codex-home"
  chmod +x "$1/Contents/Resources/codex-home"
  printf 'retain bundle data\n' >"$1/retained"
}
fixture_workflow() {
  mkdir -p "$1/Contents"
  /usr/bin/plutil -create xml1 "$1/Contents/Info.plist"
  /usr/bin/plutil -insert CodexContextsManagedWorkflow -string codex-contexts-quick-action-v1 "$1/Contents/Info.plist"
  printf 'retain workflow data\n' >"$1/retained"
}

cat >"$MUTATION_TEST_ROOT/observe-lock.py" <<'PY'
import fcntl
import os
import runpy
import sys

original_flock = fcntl.flock

def observe_flock(fd, operation):
    try:
        original_flock(fd, operation | fcntl.LOCK_NB)
    except BlockingIOError:
        with open(os.environ["MUTATION_TEST_BLOCKED"], "w"):
            pass
        original_flock(fd, operation)

fcntl.flock = observe_flock
sys.argv = sys.argv[1:]
runpy.run_path(sys.argv[0], run_name="__main__")
PY

run_mutation() (
  local command="$1"
  shift
  export HOME="$case_root/home" CODEX_HOMES_ROOT="$case_root/homes"
  export CODEX_MACOS_APP_DIR="$apps" CODEX_MACOS_SERVICES_DIR="$services"
  export CODEX_MACOS_TRASH_DIR="$case_root/trash" CODEX_MACOS_SKIP_REGISTER=1
  export MUTATION_TEST_BLOCKED="$case_root/blocked"
  python3() {
    if [[ "${1:-}" == -I && "${2:-}" == */macos_bundles.py && "${3:-}" == lock ]]; then
      shift
      command python3 -I "$MUTATION_TEST_ROOT/observe-lock.py" "$@"
      return "$?"
    fi
    command python3 "$@"
  }
  source "$MUTATION_TEST_REPO/bin/$command" "$@"
)

# Even missing preview roots must stay missing: no mkdir and no lock creation.
case_root="$MUTATION_TEST_ROOT/preview"
apps="$case_root/home/Applications"
services="$case_root/services"
run_mutation cleanup-macos-open-with >"$MUTATION_TEST_ROOT/preview.output" 2>&1
[[ ! -e "$case_root" ]] || fail 'preview created missing directories or locks'

exercise_case() {
  local resource="$1" mode="$2" command=cleanup-macos-open-with bundle lock holder mutation status=0
  local -a arguments=(--apply)
  case_root="$MUTATION_TEST_ROOT/$resource-$mode"
  apps="$case_root/home/Applications"
  services="$case_root/services"
  mkdir -p "$apps" "$services" "$case_root/homes/unit/vscode-user-data"
  case "$resource" in
    main-app|main-workflow|main-combined)
      command=uninstall-macos-open-with
      arguments=()
      if [[ "$resource" == main-combined ]]; then services="$apps"; fi
      fixture_app "$apps/Codex Project.app" org.codex-contexts.project
      fixture_workflow "$services/Open in Codex Project.workflow"
      bundle="$apps/Codex Project.app"
      lock="$(macos_install_lock_path "$apps")"
      if [[ "$resource" == main-workflow ]]; then
        bundle="$services/Open in Codex Project.workflow"
        lock="$(macos_install_lock_path "$services")"
      fi
      ;;
    app-backup)
      bundle="$apps/.codex-project-backups/Codex Project.old.app.backup"
      fixture_app "$bundle" org.codex-contexts.project
      lock="$(macos_install_lock_path "$apps")"
      ;;
    workflow-backup)
      bundle="$services/.codex-project-backups/Open in Codex Project.old.workflow.backup"
      fixture_workflow "$bundle"
      lock="$(macos_install_lock_path "$services")"
      ;;
    cleanup-handler|uninstall-handler)
      bundle="$apps/VS Code - unit.app"
      fixture_app "$bundle" org.codex-contexts.vscode.unit
      printf 'codex-contexts-vscode-open-with-v1\nunit\n' >"$bundle/Contents/Resources/codex-contexts-open-with"
      printf 'unit\n' >"$bundle/Contents/Resources/identity"
      lock="$(macos_handler_lock_path "$bundle")"
      if [[ "$resource" == uninstall-handler ]]; then
        command=uninstall-macos-open-with
        arguments=()
      fi
      ;;
    named-editor|legacy-editor)
      editor_dir="$case_root/homes/unit/vscode-editor"
      if [[ "$resource" == legacy-editor ]]; then editor_dir="$case_root/homes/unit/vscode-dock"; fi
      bundle="$editor_dir/VS Code - unit.app"
      if [[ "$resource" == named-editor ]]; then
        fixture_app "$bundle" com.microsoft.VSCode
        printf 'codex-contexts-vscode-editor-v1\n' >"$editor_dir/source"
      else
        fixture_app "$bundle" org.codex-contexts.vscode.unit
      fi
      lock="$(macos_editor_lock_path "$editor_dir")"
      ;;
  esac
  (
    macos_acquire_locks "$lock"
    touch "$case_root/held"
    await_file "$case_root/release"
  ) >"$case_root/holder.output" 2>&1 &
  holder=$!
  await_file "$case_root/held"
  run_mutation "$command" ${arguments[@]+"${arguments[@]}"} >"$case_root/mutation.output" 2>&1 &
  mutation=$!
  await_file "$case_root/blocked"
  [[ -f "$bundle/retained" ]] || fail "$resource mutated a locked bundle"
  if [[ "$mode" == foreign ]]; then
    if [[ "$resource" == *workflow* ]]; then
      /usr/bin/plutil -replace CodexContextsManagedWorkflow -string foreign "$bundle/Contents/Info.plist"
    else
      /usr/bin/plutil -replace CFBundleIdentifier -string org.example.foreign "$bundle/Contents/Info.plist"
    fi
  elif [[ "$mode" == running ]]; then
    printf '%s\n' "$$" >"$case_root/homes/unit/vscode-user-data/code.lock"
  fi
  touch "$case_root/release"
  wait "$holder" || fail 'lock holder failed'
  wait "$mutation" || status=$?
  if [[ "$mode" == normal ]]; then
    if [[ "$status" != 0 ]]; then cat "$case_root/mutation.output" >&2; fail "$resource removal failed"; fi
    [[ ! -e "$bundle" ]] || fail "$resource kept an owned unlocked bundle"
  else
    [[ -f "$bundle/retained" ]] || fail "$resource removed a bundle changed while waiting"
    if [[ "$resource" == main-* ]]; then
      [[ "$status" != 0 && ! -e "$case_root/trash" ]] || fail 'uninstall did not refuse changed ownership before moving other bundles'
    else
      [[ "$status" == 0 ]] || fail "$resource did not keep a changed/running bundle safely"
      grep -Eq 'ownership changed while waiting|Kept running editor' "$case_root/mutation.output" || fail 'missing deferred-removal diagnostic'
    fi
  fi
}

for resource in main-app main-workflow app-backup workflow-backup cleanup-handler uninstall-handler named-editor legacy-editor; do
  exercise_case "$resource" normal
  exercise_case "$resource" foreign
done
exercise_case main-combined normal
exercise_case named-editor running
printf 'Mac mutation lock tests passed.\n'
