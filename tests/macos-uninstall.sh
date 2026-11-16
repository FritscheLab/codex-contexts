#!/usr/bin/env bash
# Uninstallation must only move owned bundles in the selected install directory.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || exit 0
UNINSTALL_TEST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
UNINSTALL_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-uninstall-test.XXXXXX")"
trap 'rm -rf -- "$UNINSTALL_TEST_ROOT"' EXIT
fail() { printf 'Uninstall test failure: %s\n' "$*" >&2; exit 1; }
fixture_app() {
  mkdir -p "$1/Contents/Resources"
  /usr/bin/plutil -create xml1 "$1/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleIdentifier -string "$2" "$1/Contents/Info.plist"
  printf '#!/bin/bash\n' >"$1/Contents/Resources/codex-home"
  chmod +x "$1/Contents/Resources/codex-home"
}
apps="$UNINSTALL_TEST_ROOT/apps"
app="$apps/Codex Project.app"
run_uninstaller() {
  CODEX_MACOS_APP_DIR="$apps" \
    CODEX_MACOS_SERVICES_DIR="$UNINSTALL_TEST_ROOT/services" \
    CODEX_MACOS_TRASH_DIR="$UNINSTALL_TEST_ROOT/trash" \
    CODEX_MACOS_SKIP_REGISTER=1 \
    "$UNINSTALL_TEST_REPO/bin/uninstall-macos-open-with" >"$UNINSTALL_TEST_ROOT/output" 2>&1
}
fixture_app "$app" org.example.namesake
if run_uninstaller; then fail 'accepted an unrelated namesake application'; fi
[[ -x "$app/Contents/Resources/codex-home" && ! -e "$UNINSTALL_TEST_ROOT/trash" ]] ||
  fail 'changed files before refusing the unrelated application'
grep -Fq 'refusing to remove an unrelated app' "$UNINSTALL_TEST_ROOT/output" ||
  fail 'unrelated application refusal was not explained'

/usr/bin/plutil -replace CFBundleIdentifier -string org.codex-contexts.project "$app/Contents/Info.plist"
mv "$app/Contents/Resources/codex-home" "$UNINSTALL_TEST_ROOT/helper"
ln -s "$UNINSTALL_TEST_ROOT/helper" "$app/Contents/Resources/codex-home"
if run_uninstaller; then fail 'accepted symlinked ownership evidence'; fi
[[ -L "$app/Contents/Resources/codex-home" ]] || fail 'changed the symlinked helper'
unlink "$app/Contents/Resources/codex-home"
mv "$UNINSTALL_TEST_ROOT/helper" "$app/Contents/Resources/codex-home"

fixture_app "$apps/VS Code - foreign.app" org.example.unrelated
fixture_app "$apps/VS Code - incomplete.app" org.codex-contexts.vscode.incomplete
printf 'codex-contexts-vscode-open-with-v1\n' >"$apps/VS Code - incomplete.app/Contents/Resources/codex-contexts-open-with"
fixture_app "$apps/VS Code - owned.app" org.codex-contexts.vscode.owned
printf 'codex-contexts-vscode-open-with-v1\nowned\n' >"$apps/VS Code - owned.app/Contents/Resources/codex-contexts-open-with"
printf 'owned\n' >"$apps/VS Code - owned.app/Contents/Resources/identity"
run_uninstaller
[[ ! -e "$app" && ! -e "$apps/VS Code - owned.app" ]] || fail 'kept owned selected applications'
[[ -d "$apps/VS Code - foreign.app" ]] || fail 'moved an unrelated VS Code namesake'
[[ -d "$apps/VS Code - incomplete.app" ]] || fail 'moved a handler with incomplete ownership evidence'
find "$UNINSTALL_TEST_ROOT/trash" -maxdepth 1 -type d -name 'Codex Project.*.app' \
  -print -quit | grep -q . || fail 'owned app was not moved to Trash'
printf 'Mac uninstall tests passed.\n'
