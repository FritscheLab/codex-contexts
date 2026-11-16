#!/usr/bin/env bash
# Exercise deletion boundaries with synthetic bundles, without registration.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || exit 0
CLEANUP_TEST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CLEANUP_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-cleanup-test.XXXXXX")"
trap 'rm -rf -- "$CLEANUP_TEST_ROOT"' EXIT
fail() { printf 'Cleanup test failure: %s\n' "$*" >&2; exit 1; }
fixture_app() {
  mkdir -p "$1/Contents/Resources"
  /usr/bin/plutil -create xml1 "$1/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleIdentifier -string "$2" "$1/Contents/Info.plist"
  printf '#!/bin/bash\n' >"$1/Contents/Resources/codex-home"
  chmod +x "$1/Contents/Resources/codex-home"
}
apps="$CLEANUP_TEST_ROOT/home/Applications"
homes="$CLEANUP_TEST_ROOT/identities"
backup="$apps/.codex-project-backups/Codex Project.old.app.backup"
foreign="$apps/.codex-project-backups/Codex Project.foreign.app.backup"
legacy="$apps/Codex Project.backup.old.app"
handler="$apps/VS Code - unit.app"
editor="$homes/unit/vscode-editor/VS Code - unit.app"
running="$homes/running/vscode-editor/VS Code - running.app"
fixture_app "$apps/Codex Project.app" org.codex-contexts.project
fixture_app "$backup" org.codex-contexts.project
fixture_app "$legacy" org.codex-contexts.project
fixture_app "$foreign" org.example.unrelated
fixture_app "$handler" org.codex-contexts.vscode.unit
printf 'codex-contexts-vscode-open-with-v1\nunit\n' >"$handler/Contents/Resources/codex-contexts-open-with"
printf 'unit\n' >"$handler/Contents/Resources/identity"
fixture_app "$apps/VS Code - foreign.app" org.example.unrelated
fixture_app "$apps/VS Code - incomplete.app" org.codex-contexts.vscode.incomplete
printf 'codex-contexts-vscode-open-with-v1\n' >"$apps/VS Code - incomplete.app/Contents/Resources/codex-contexts-open-with"
symlink_helper="$apps/.codex-project-backups/Codex Project.borrowed.app.backup"
fixture_app "$symlink_helper" org.codex-contexts.project
printf 'retain borrowed helper\n' >"$CLEANUP_TEST_ROOT/borrowed-helper"
chmod +x "$CLEANUP_TEST_ROOT/borrowed-helper"
unlink "$symlink_helper/Contents/Resources/codex-home"
ln -s "$CLEANUP_TEST_ROOT/borrowed-helper" "$symlink_helper/Contents/Resources/codex-home"
for bundle in "$editor" "$running"; do
  fixture_app "$bundle" com.microsoft.VSCode
  printf 'codex-contexts-vscode-editor-v1\n' >"$(dirname "$bundle")/source"
done
ln -s "$foreign" "$apps/.codex-project-backups/Codex Project.symlink.app.backup"
mkdir -p "$homes/unit/vscode-user-data" "$homes/running/vscode-user-data"
printf 'private fixture\n' >"$homes/unit/vscode-user-data/retained"
printf '%s\n' "$$" >"$homes/running/vscode-user-data/code.lock"
run_cleanup() {
  env HOME="$CLEANUP_TEST_ROOT/home" CODEX_HOMES_ROOT="$homes" \
    CODEX_MACOS_SERVICES_DIR="$CLEANUP_TEST_ROOT/services" \
    CODEX_MACOS_APP_DIR="$apps" CODEX_MACOS_SKIP_REGISTER=1 \
    "$CLEANUP_TEST_REPO/bin/cleanup-macos-open-with" "$@" >"$CLEANUP_TEST_ROOT/output" 2>&1
}
run_cleanup --backups-only
[[ -d "$backup" && -d "$legacy" ]] || fail 'preview removed backups'
run_cleanup
[[ -d "$handler" && -d "$editor" ]] || fail 'preview removed applications'
[[ ! -e "$apps/.codex-contexts-install.lock" &&
  ! -e "$apps/.codex-contexts-vscode-unit.lock" &&
  ! -e "$homes/unit/vscode-editor/.build-lock" &&
  ! -e "$CLEANUP_TEST_ROOT/services" ]] || fail 'preview created lock files or directories'
grep -Fq 'Preview only. Nothing changed.' "$CLEANUP_TEST_ROOT/output" || fail 'preview was not identified'
run_cleanup --backups-only --apply
[[ ! -e "$backup" && ! -e "$legacy" ]] || fail 'kept obsolete owned backups'
[[ -d "$handler" && -d "$editor" ]] || fail 'backup-only cleanup removed active launchers'
run_cleanup --apply
[[ ! -e "$handler" && ! -e "$editor" ]] || fail 'kept redundant generated applications'
[[ -d "$foreign" && -d "$apps/VS Code - foreign.app" ]] || fail 'removed unrelated apps'
[[ -d "$apps/VS Code - incomplete.app" && -d "$symlink_helper" ]] || fail 'removed bundles with incomplete or symlinked ownership evidence'
[[ "$(cat "$CLEANUP_TEST_ROOT/borrowed-helper")" == 'retain borrowed helper' ]] || fail 'changed borrowed ownership evidence'
[[ -L "$apps/.codex-project-backups/Codex Project.symlink.app.backup" ]] || fail 'followed a symlink'
[[ -d "$apps/Codex Project.app" ]] || fail 'removed the main chooser'
[[ -d "$running" ]] || fail 'removed a running editor'
grep -Fq 'Kept running editor:' "$CLEANUP_TEST_ROOT/output" || fail 'did not report deferred cleanup'
[[ "$(cat "$homes/unit/vscode-user-data/retained")" == 'private fixture' ]] || fail 'changed user data'
rm "$homes/running/vscode-user-data/code.lock"
run_cleanup --apply
[[ ! -e "$running" ]] || fail 'kept a stopped editor'
run_cleanup --apply
workflow_backup="$CLEANUP_TEST_ROOT/services/.codex-project-backups/Open in Codex Project.old.workflow.backup"
mkdir -p "$workflow_backup/Contents"
/usr/bin/plutil -create xml1 "$workflow_backup/Contents/Info.plist"
/usr/bin/plutil -insert CodexContextsManagedWorkflow -string codex-contexts-quick-action-v1 "$workflow_backup/Contents/Info.plist"
# Automator workflows cannot be unregistered as apps. Fail any accidental call.
(
  export HOME="$CLEANUP_TEST_ROOT/home" CODEX_HOMES_ROOT="$homes"
  export CODEX_MACOS_APP_DIR="$apps" CODEX_MACOS_SERVICES_DIR="$CLEANUP_TEST_ROOT/services" CODEX_MACOS_SKIP_REGISTER=0
  function /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister {
    return 99
  }
  source "$CLEANUP_TEST_REPO/bin/cleanup-macos-open-with" --backups-only --apply
) >"$CLEANUP_TEST_ROOT/output" 2>&1 || fail 'tried to unregister a Quick Action backup as an app'
[[ ! -e "$workflow_backup" ]] || fail 'kept the obsolete Quick Action backup'
printf 'Mac cleanup tests passed.\n'
