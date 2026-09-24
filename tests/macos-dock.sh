#!/usr/bin/env bash
# Offline tests: real bundle/signing/copy tools, fake VS Code, no GUI launch.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || exit 0
DOCK_TEST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DOCK_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-dock-test.XXXXXX")"
DOCK_TEST_ROOT="$(cd "$DOCK_TEST_ROOT" && pwd -P)"
trap 'rm -rf -- "$DOCK_TEST_ROOT"' EXIT
export CODEX_HOMES_ROOT="$DOCK_TEST_ROOT/identity homes"
export DIRENV_CONFIG="$DOCK_TEST_ROOT/direnv-config"
export XDG_DATA_HOME="$DOCK_TEST_ROOT/xdg-data"
export CODEX_SKILLS_SOURCE="$DOCK_TEST_ROOT/empty-skills"
export CODEX_VSCODE_DOCK_LABEL=1
export CODEX_MACOS_SKIP_REGISTER=1
unset CODEX_HOME CODEX_IDENTITY DIRENV_DIFF DIRENV_DIR DIRENV_FILE DIRENV_WATCHES
source "$DOCK_TEST_REPO/bin/codex-home"

fail() { printf 'Dock test failure: %s\n' "$*" >&2; exit 1; }
quiet_check() {
  if "$@" 2>"$DOCK_TEST_ROOT/error"; then return 0; fi
  cat "$DOCK_TEST_ROOT/error" >&2
  fail "command failed: $1"
}
sign_source() { /usr/bin/codesign --force --sign - "$fake_app" >/dev/null 2>&1; }
set_source_version() {
  /usr/bin/plutil -replace CFBundleVersion -string "$1" "$fake_contents/Info.plist"
  sign_source
}

fake_app="$DOCK_TEST_ROOT/"'Code $mock [one].app'
fake_contents="$fake_app/Contents"
fake_cli="$fake_contents/Resources/app/bin/code"
fake_executable="$fake_contents/MacOS/Code"
mkdir -p "$fake_contents/MacOS" "$(dirname "$fake_cli")" "$DOCK_TEST_ROOT/bin" \
  "$DOCK_TEST_ROOT/extensions" "$CODEX_SKILLS_SOURCE"
/usr/bin/plutil -create xml1 "$fake_contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string com.microsoft.VSCode "$fake_contents/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string Code "$fake_contents/Info.plist"
/usr/bin/plutil -insert CFBundleDisplayName -string Code "$fake_contents/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string 1 "$fake_contents/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$fake_contents/Info.plist"
printf '#!/bin/bash\nprintf "raw executable must not run\\n" >&2\nexit 91\n' >"$fake_executable"
cat >"$fake_cli" <<'EOF'
#!/bin/bash
set -eu
printf '%s\n' "$0" "$@" >"$CODEX_DOCK_TEST_ARGS"
printf '%s|%s|%s\n' "$CODEX_HOME" "$CODEX_IDENTITY" "${DOCK_TEST_KEY:-}" >"$CODEX_DOCK_TEST_ENV"
EOF
chmod +x "$fake_executable" "$fake_cli"
sign_source
ln -s '../Code $mock [one].app/Contents/Resources/app/bin/code' "$DOCK_TEST_ROOT/bin/code"
export PATH="$DOCK_TEST_ROOT/bin:$PATH"
export CODEX_VSCODE_CLI="$DOCK_TEST_ROOT/bin/code"
export CODEX_VSCODE_EXTENSIONS_DIR="$DOCK_TEST_ROOT/extensions"
export CODEX_DOCK_TEST_ARGS="$DOCK_TEST_ROOT/args"
export CODEX_DOCK_TEST_ENV="$DOCK_TEST_ROOT/env"
[[ "$(macos_vscode_executable "$CODEX_VSCODE_CLI")" == "$fake_executable" ]] || fail 'symlinked CLI resolution'
if macos_vscode_executable /custom/wrapper >/dev/null; then fail 'accepted an unrelated CLI wrapper'; fi

create_subscription dock-unit >/dev/null
create_subscription dock-other >/dev/null
unit_home="$CODEX_HOMES_ROOT/dock-unit"
printf 'DOCK_TEST_KEY=synthetic-not-for-bundle\n' >"$unit_home/.env"
project_one="$DOCK_TEST_ROOT/"'project $one [x]'
project_two="$DOCK_TEST_ROOT/project two"
mkdir -p "$project_one" "$project_two"
write_project_files dock-unit "$project_one" >/dev/null
write_project_files dock-unit "$project_two" >/dev/null
direnv allow "$project_one" >/dev/null 2>&1
direnv allow "$project_two" >/dev/null 2>&1

app="$(prepare_macos_vscode_editor dock-unit "$unit_home" "$fake_executable")"
named_cli="$app/Contents/Resources/app/bin/code"
[[ "$app" == "$unit_home/vscode-editor/VS Code - dock-unit.app" ]] || fail 'incorrect named editor path'
/usr/bin/codesign --verify --strict "$app"
diff -qr "$fake_app" "$app" >/dev/null || fail 'signed bundle contents were modified'
[[ -f "$unit_home/vscode-editor/source" ]] || fail 'ownership/source marker missing'
if grep -Rq 'synthetic-not-for-bundle' "$app"; then fail 'serialized a credential'; fi
inode="$(stat -f %i "$app")"
prepare_macos_vscode_editor dock-unit "$unit_home" "$fake_executable" >/dev/null
[[ "$(stat -f %i "$app")" == "$inode" ]] || fail 'rebuilt an unchanged editor'

# Both cold and warm launches use the complete named bundle's CLI.
quiet_check "$DOCK_TEST_REPO/bin/codex-home" vscode dock-unit "$project_one" >/dev/null
[[ "$(head -n 1 "$CODEX_DOCK_TEST_ARGS")" == "$named_cli" ]] || fail 'cold launch bypassed named CLI'
grep -Fxq -- "$project_one/.vscode/project \$one [x].code-workspace" "$CODEX_DOCK_TEST_ARGS" || fail 'project path was split or expanded'
grep -Fxq -- "$unit_home|dock-unit|synthetic-not-for-bundle" "$CODEX_DOCK_TEST_ENV" || fail 'wrong identity environment'
printf '%s' "$$" >"$unit_home/vscode-user-data/code.lock"
quiet_check "$DOCK_TEST_REPO/bin/codex-home" vscode dock-unit "$project_two" >/dev/null
[[ "$(head -n 1 "$CODEX_DOCK_TEST_ARGS")" == "$named_cli" ]] || fail 'warm launch bypassed named CLI'

# A live/reused PID only defers refresh; it never switches launch routing.
set_source_version 2
prepare_macos_vscode_editor dock-unit "$unit_home" "$fake_executable" \
  >/dev/null 2>"$DOCK_TEST_ROOT/pending"
grep -Fq 'update pending' "$DOCK_TEST_ROOT/pending" || fail 'running update was not reported'
[[ "$(stat -f %i "$app")" == "$inode" ]] || fail 'replaced a running editor'
quiet_check "$DOCK_TEST_REPO/bin/codex-home" vscode dock-unit "$project_one" >/dev/null
[[ "$(head -n 1 "$CODEX_DOCK_TEST_ARGS")" == "$named_cli" ]] || fail 'pending update changed launch route'
printf 'not-a-pid' >"$unit_home/vscode-user-data/code.lock"
if macos_vscode_is_running "$unit_home/vscode-user-data"; then fail 'accepted invalid PID'; fi
rm "$unit_home/vscode-user-data/code.lock"

# A leftover kernel-lock file does not block refresh after its owner exits.
printf 'stale owner\n' >"$unit_home/vscode-editor/.build-lock"
prepare_macos_vscode_editor dock-unit "$unit_home" "$fake_executable" >/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == 2 ]] || fail 'source update was not installed'
diff -qr "$fake_app" "$app" >/dev/null || fail 'updated editor differs from source'
/usr/bin/codesign --verify --strict "$app"
inode="$(stat -f %i "$app")"

# Failed verification leaves the installed copy intact.
/usr/bin/plutil -replace CFBundleVersion -string 3 "$fake_contents/Info.plist"
if prepare_macos_vscode_editor dock-unit "$unit_home" "$fake_executable" >/dev/null 2>&1; then
  fail 'installed an invalid source signature'
fi
[[ "$(stat -f %i "$app")" == "$inode" ]] || fail 'failed preparation replaced editor'
sign_source

# Concurrent rebuild requests serialize and both receive the same valid app.
prepare_macos_vscode_editor dock-unit "$unit_home" "$fake_executable" >"$DOCK_TEST_ROOT/copy-one" &
copy_one_pid=$!
prepare_macos_vscode_editor dock-unit "$unit_home" "$fake_executable" >"$DOCK_TEST_ROOT/copy-two" &
copy_two_pid=$!
wait "$copy_one_pid" || fail 'first concurrent preparation failed'
wait "$copy_two_pid" || fail 'second concurrent preparation failed'
cmp -s "$DOCK_TEST_ROOT/copy-one" "$DOCK_TEST_ROOT/copy-two" || fail 'concurrent preparation chose different apps'
diff -qr "$fake_app" "$app" >/dev/null || fail 'concurrent preparation damaged bundle'

# A failed installation after moving the old app restores that exact copy.
inode="$(stat -f %i "$app")"
set_source_version 4
if (
  mv() {
    if [[ "$1" == *'/.build.'*'/VS Code - dock-unit.app' && "$2" == "$app" ]]; then
      return 1
    fi
    command mv "$@"
  }
  prepare_macos_vscode_editor dock-unit "$unit_home" "$fake_executable"
) >/dev/null 2>&1; then fail 'ignored failed installation'; fi
[[ "$(stat -f %i "$app")" == "$inode" ]] || fail 'failed installation did not restore previous app'
prepare_macos_vscode_editor dock-unit "$unit_home" "$fake_executable" >/dev/null

quiet_check env CODEX_VSCODE_DOCK_LABEL=0 "$DOCK_TEST_REPO/bin/codex-home" vscode dock-unit "$project_one" >/dev/null
[[ "$(head -n 1 "$CODEX_DOCK_TEST_ARGS")" == "$CODEX_VSCODE_CLI" ]] || fail 'CLI opt-out was ignored'

# Saved-project invocations use the named editor's CLI.
printf '%s\n' "$project_two" >"$DOCK_TEST_ROOT/legacy-last-project"
quiet_check "$DOCK_TEST_REPO/bin/codex-home" _vscode-dock dock-unit "$DOCK_TEST_ROOT/legacy-last-project" >/dev/null
[[ "$(head -n 1 "$CODEX_DOCK_TEST_ARGS")" == "$named_cli" ]] || fail '_vscode-dock bypassed named CLI'

# Invalid/missing environments fail before any editor CLI can run.
direnv deny "$project_two" >/dev/null 2>&1
rm "$CODEX_DOCK_TEST_ARGS"
if "$DOCK_TEST_REPO/bin/codex-home" vscode dock-unit "$project_two" >/dev/null 2>&1; then fail 'opened denied project'; fi
[[ ! -e "$CODEX_DOCK_TEST_ARGS" ]] || fail 'launched denied project'
mv "$project_two/.envrc" "$project_two/.envrc.saved"
if CODEX_IDENTITY=dock-unit CODEX_HOME="$unit_home" \
  "$DOCK_TEST_REPO/bin/codex-home" vscode dock-unit "$project_two" >/dev/null 2>&1; then fail 'accepted inherited identity without envrc'; fi
[[ ! -e "$CODEX_DOCK_TEST_ARGS" ]] || fail 'launched missing environment'

# Refuse unowned destinations and symlinked ownership files.
foreign="$CODEX_HOMES_ROOT/dock-other/vscode-editor/VS Code - dock-other.app"
mkdir -p "$foreign"
if prepare_macos_vscode_editor dock-other "$CODEX_HOMES_ROOT/dock-other" "$fake_executable" >/dev/null 2>&1; then fail 'overwrote unowned app'; fi
mv "$unit_home/vscode-editor/source" "$unit_home/vscode-editor/source.saved"
ln -s "$DOCK_TEST_ROOT/untouched" "$unit_home/vscode-editor/source"
if prepare_macos_vscode_editor dock-unit "$unit_home" "$fake_executable" >/dev/null 2>&1; then fail 'followed marker symlink'; fi
[[ ! -e "$DOCK_TEST_ROOT/untouched" ]] || fail 'wrote through marker symlink'
printf 'Mac Dock tests passed.\n'
