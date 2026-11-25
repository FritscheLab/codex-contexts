#!/usr/bin/env bash
# Sourceable macOS bundle support. Loading this file performs no app actions.

macos_data_helper() {
  python3 -I "$CODEX_CONTEXTS_LIB/macos_bundles.py" "$@"
}

macos_acquire_locks() {
  local timeout="" lock_path
  local -a arguments=()
  if [[ "${1:-}" == --timeout ]]; then
    timeout="$2"
    shift 2
    arguments=(--timeout "$timeout")
  fi
  [[ $# -ge 1 && $# -le 2 ]] || die "one or two bundle lock paths are required"
  for lock_path in "$@"; do
    [[ ! -L "$lock_path" && ( ! -e "$lock_path" || -f "$lock_path" ) ]] ||
      die "refusing an unsafe bundle lock: $lock_path"
  done
  # Append-open avoids truncation. Keep these stable files after releasing locks.
  exec 9>>"$1" || return
  arguments+=(9 "$1")
  if [[ $# == 2 ]]; then
    exec 10>>"$2" || return
    arguments+=(10 "$2")
  fi
  # The shell retains the inherited descriptors after the Python helper exits.
  macos_data_helper lock "${arguments[@]}"
}

macos_bundle_identity() {
  macos_data_helper identity "$1"
}

macos_rename_bundle() {
  macos_data_helper rename "$1" "$2" "$3"
}

macos_owned_bundle() {
  macos_data_helper owned "$@"
}

macos_install_lock_path() {
  printf '%s/.codex-contexts-install.lock\n' "$1"
}

macos_handler_lock_path() {
  macos_data_helper handler-lock "$1"
}

macos_editor_lock_path() {
  printf '%s/.build-lock\n' "$1"
}

macos_bundle_launcher() {
  local contents="$1" resources source entry_dir
  resources="$contents/Resources"
  entry_dir="$(dirname "$CODEX_CONTEXTS_LAUNCHER")"
  source="$entry_dir/VSCodeIdentity.applescript"
  [[ -f "$source" ]] || source="$entry_dir/../macos/VSCodeIdentity.applescript"
  [[ -f "$source" ]] || die "missing the VS Code Finder handler source"
  mkdir -p "$resources" "$contents/config" || return
  cp "$CODEX_CONTEXTS_LAUNCHER" "$resources/codex-home" || return
  cp -R "$CODEX_CONTEXTS_LIB" "$resources/libexec" || return
  cp "$source" "$resources/VSCodeIdentity.applescript" || return
  cp "$entry_dir/../config/umgpt-models.toml" "$contents/config/umgpt-models.toml" || return
  chmod 700 "$resources/codex-home"
}

macos_vscode_executable() {
  local cli="$1" target contents executable identifier hops=0
  while [[ -L "$cli" ]]; do
    hops=$((hops + 1))
    [[ "$hops" -le 40 ]] || return 1
    target="$(readlink "$cli")" || return 1
    if [[ "$target" == /* ]]; then cli="$target"; else cli="$(dirname "$cli")/$target"; fi
  done
  case "$cli" in
    *.app/Contents/Resources/app/bin/code|*.app/Contents/Resources/app/bin/code-insiders) ;;
    *) return 1 ;;
  esac
  contents="$(cd "$(dirname "$cli")/../../.." && pwd -P)" || return 1
  identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$contents/Info.plist" 2>/dev/null)" || return 1
  case "$identifier" in com.microsoft.VSCode|com.microsoft.VSCodeInsiders) ;; *) return 1 ;; esac
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$contents/Info.plist" 2>/dev/null)" || return 1
  [[ -n "$executable" && "$executable" != */* && -x "$contents/MacOS/$executable" ]] || return 1
  printf '%s\n' "$contents/MacOS/$executable"
}

macos_vscode_is_running() {
  local data="$1" pid
  [[ -f "$data/code.lock" ]] || return 1
  pid="$(cat "$data/code.lock")"
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  # A stale/reused PID can only defer a copy refresh. Routing always uses the
  # chosen editor's CLI with this identity's explicit user-data directory.
  kill -0 "$pid" 2>/dev/null
}

macos_vscode_source_metadata() {
  local app="$1" executable="$2" plist_hash executable_stat product_hash=""
  plist_hash="$(shasum -a 256 "$app/Contents/Info.plist")" || return 1
  executable_stat="$(/usr/bin/stat -f '%d:%i:%m:%c:%z' "$executable")" || return 1
  if [[ -f "$app/Contents/Resources/app/product.json" ]]; then
    product_hash="$(shasum -a 256 "$app/Contents/Resources/app/product.json")" || return 1
  fi
  printf 'codex-contexts-vscode-editor-v1\n%s\n%s\n%s\n%s\n' \
    "$app" "$plist_hash" "$executable_stat" "$product_hash"
}

macos_vscode_open_with_path() {
  printf '%s/Applications/VS Code - %s.app\n' "$HOME" "$1"
}

macos_vscode_unregister_editor() {
  local app="$1"
  local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
  [[ "${CODEX_MACOS_SKIP_REGISTER:-0}" != "1" ]] || return 0
  [[ -d "$app" && -x "$lsregister" ]] || return 0
  "$lsregister" -u "$app" >/dev/null 2>&1 || true
}

ensure_macos_vscode_open_with() (
  set -e
  umask 077
  local name="$1" home="$2" app_dir app source marker metadata build candidate info_plist
  local lock previous_id="" candidate_id=""
  local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
  local plist_buddy="/usr/libexec/PlistBuddy"
  local runtime_app="$home/vscode-editor/VS Code - $name.app"
  [[ "${CODEX_MACOS_SKIP_REGISTER:-0}" != "1" ]] || return 0
  validate_name "$name"
  app="$(macos_vscode_open_with_path "$name")" || die "could not determine the VS Code Finder app path"
  app_dir="$(dirname "$app")"
  source="$SCRIPT_DIR/VSCodeIdentity.applescript"
  [[ -f "$source" ]] || source="$REPOSITORY_ROOT/macos/VSCodeIdentity.applescript"
  [[ -f "$source" ]] || die "missing the VS Code Finder handler source"
  [[ -f "$CODEX_DATA_HELPER" ]] || die "missing the Python data helper"
  [[ -f "$SCRIPT_DIR/../config/umgpt-models.toml" ]] || die "missing bundled U-M GPT model defaults"
  command -v osacompile >/dev/null 2>&1 || die "osacompile is required for VS Code Finder entries"
  [[ -x /usr/bin/codesign && -x "$plist_buddy" ]] || die "required macOS application tools were not found"
  [[ ! -L "$app_dir" ]] || die "refusing a symbolic link at $app_dir"
  mkdir -p "$app_dir" || die "could not create $app_dir"
  app_dir="$(cd "$app_dir" && pwd -P)" || die "could not open $app_dir"
  app="$app_dir/VS Code - $name.app"
  lock="$(macos_handler_lock_path "$app")" || die "could not determine the Finder app lock"
  macos_acquire_locks "$lock" || die "could not lock the VS Code Finder app"
  [[ ! -L "$app" ]] || die "refusing a symbolic link at $app"
  marker="$app/Contents/Resources/codex-contexts-open-with"
  if [[ -e "$app" ]]; then
    previous_id="$(macos_owned_bundle handler "$app" "$name")" ||
      die "refusing to replace an unowned Finder app: $app"
  fi
  metadata="$(macos_data_helper fingerprint "$source" "$CODEX_CONTEXTS_LAUNCHER" \
    "$CODEX_CONTEXTS_LIB" "$SCRIPT_DIR/../config/umgpt-models.toml")" || return 1
  metadata="$(printf 'codex-contexts-vscode-open-with-v1\n%s\n%s' "$name" "$metadata")"
  marker="$app/Contents/Resources/codex-contexts-open-with"
  if [[ -f "$marker" ]] && [[ "$(cat "$marker")" == "$metadata" ]]; then
    macos_vscode_unregister_editor "$runtime_app"
    [[ ! -x "$lsregister" ]] || "$lsregister" -f "$app" >/dev/null 2>&1 || true
    return 0
  fi

  build="$(mktemp -d "$app_dir/.vscode-open-with.XXXXXX")" || die "could not stage the VS Code Finder app"
  cleanup_vscode_open_with() {
    local status=$? failed=0
    if [[ "$status" -ne 0 ]]; then
      if [[ -n "$candidate_id" && -e "$app" &&
        "$(macos_bundle_identity "$app")" == "$candidate_id" ]]; then
        macos_rename_bundle "$app" "$build/failed.app" "$candidate_id" || failed=1
      fi
      if [[ -e "$build/previous.app" ]]; then
        macos_rename_bundle "$build/previous.app" "$app" "$previous_id" || failed=1
      fi
      if [[ "$failed" != 0 ]]; then
        printf 'Finder app recovery incomplete; previous components preserved at %s for %s.\n' \
          "$build" "$app" >&2
        return "$status"
      fi
    fi
    rm -rf -- "$build"
    return "$status"
  }
  trap cleanup_vscode_open_with EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  candidate="$build/VS Code - $name.app"
  osacompile -o "$candidate" "$source" || die "could not compile the VS Code Finder app"
  # Callers may handle failure with ||, disabling Bash's errexit here.
  macos_bundle_launcher "$candidate/Contents" || die "could not bundle the Finder app launcher resources"
  printf '%s\n' "$name" >"$candidate/Contents/Resources/identity" || die "could not record the Finder app identity"
  printf '%s\n' "$metadata" >"$candidate/Contents/Resources/codex-contexts-open-with" ||
    die "could not record the Finder app ownership marker"
  info_plist="$candidate/Contents/Info.plist"
  "$plist_buddy" -c 'Delete :CFBundleIdentifier' "$info_plist" >/dev/null 2>&1 || true
  "$plist_buddy" -c "Add :CFBundleIdentifier string org.codex-contexts.vscode.$name" "$info_plist" || die "could not configure the Finder app identifier"
  "$plist_buddy" -c 'Delete :CFBundleName' "$info_plist" >/dev/null 2>&1 || true
  "$plist_buddy" -c "Add :CFBundleName string VS Code - $name" "$info_plist" || die "could not configure the Finder app name"
  "$plist_buddy" -c 'Delete :CFBundleDisplayName' "$info_plist" >/dev/null 2>&1 || true
  "$plist_buddy" -c "Add :CFBundleDisplayName string VS Code - $name" "$info_plist" || die "could not configure the Finder app display name"
  "$plist_buddy" -c 'Delete :LSUIElement' "$info_plist" >/dev/null 2>&1 || true
  "$plist_buddy" -c 'Add :LSUIElement bool true' "$info_plist" || die "could not configure the Finder app UI behavior"
  "$plist_buddy" -c 'Delete :CFBundleDocumentTypes' "$info_plist" >/dev/null 2>&1 || true
  "$plist_buddy" -c 'Add :CFBundleDocumentTypes array' "$info_plist" || die "could not configure Finder document types"
  "$plist_buddy" -c 'Add :CFBundleDocumentTypes:0 dict' "$info_plist" || die "could not configure the Finder folder handler"
  "$plist_buddy" -c 'Add :CFBundleDocumentTypes:0:CFBundleTypeName string Folder' "$info_plist" || die "could not configure the Finder folder type"
  "$plist_buddy" -c 'Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Editor' "$info_plist" || die "could not configure the Finder folder role"
  "$plist_buddy" -c 'Add :CFBundleDocumentTypes:0:LSHandlerRank string Alternate' "$info_plist" || die "could not configure the Finder handler rank"
  "$plist_buddy" -c 'Add :CFBundleDocumentTypes:0:LSItemContentTypes array' "$info_plist" || die "could not configure Finder content types"
  "$plist_buddy" -c 'Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string public.folder' "$info_plist" || die "could not configure the Finder folder content type"
  chmod 700 "$candidate/Contents/Resources/codex-home" || die "could not make the Finder app helper executable"
  /usr/bin/codesign --force --deep --sign - "$candidate" >/dev/null || die "could not sign the VS Code Finder app"
  candidate_id="$(macos_bundle_identity "$candidate")"
  if [[ -n "$previous_id" ]]; then
    macos_rename_bundle "$app" "$build/previous.app" "$previous_id" || die "could not stage the old VS Code Finder app"
  fi
  macos_rename_bundle "$candidate" "$app" "$candidate_id" || die "could not install $app"
  macos_vscode_unregister_editor "$runtime_app"
  if [[ -x "$lsregister" ]]; then "$lsregister" -f "$app" >/dev/null 2>&1 || true; fi
)

# Preserve the vendor signature by changing only the outer bundle filename.
# APFS clones share data blocks; cp falls back to a normal copy.
# Keep ownership and source metadata outside the signed bundle.
prepare_macos_vscode_editor() (
  set -e
  umask 077
  local name="$1" home="$2" executable="$3"
  local cache app marker source_app metadata build candidate status previous_id="" candidate_id=""
  cache="$home/vscode-editor"
  [[ ! -L "$cache" ]] || die "refusing a symbolic link at $cache"
  mkdir -p "$cache" || die "could not create the named editor directory: $cache"
  cache="$(cd "$cache" && pwd -P)" || die "could not open the named editor directory"
  macos_acquire_locks --timeout 20 "$(macos_editor_lock_path "$cache")" || die "could not lock the named editor"
  app="$cache/VS Code - $name.app"
  marker="$cache/source"
  [[ ! -L "$app" && ! -L "$marker" && ! -L "$cache/.build-lock" ]] ||
    die "refusing symlinked named editor files"
  if [[ -e "$marker" ]]; then
    [[ -f "$marker" && "$(sed -n '1p' "$marker")" == 'codex-contexts-vscode-editor-v1' ]] ||
      die "refusing an unrecognized named editor marker: $marker"
  fi
  if [[ -e "$app" ]]; then
    previous_id="$(macos_owned_bundle named-editor "$app")" || die "refusing to replace an unowned named editor: $app"
  fi
  source_app="$(dirname "$(dirname "$(dirname "$executable")")")"
  validate_single_line "VS Code application path" "$source_app"
  if [[ "$source_app" == "$app" ]]; then
    printf '%s\n' "$app"
    exit 0
  fi
  metadata="$(macos_vscode_source_metadata "$source_app" "$executable")" ||
    die "could not inspect the source VS Code application"
  if [[ -d "$app" && "$(cat "$marker")" == "$metadata" ]]; then
    printf '%s\n' "$app"
    exit 0
  fi
  if [[ -d "$app" ]] && macos_vscode_is_running "$home/vscode-user-data"; then
    printf 'VS Code update pending for %s; quit this identity and reopen through Codex Project to refresh its named editor.\n' "$name" >&2
    printf '%s\n' "$app"
    exit 0
  fi

  build="$(mktemp -d "$cache/.build.XXXXXX")" || die "could not stage the named editor"
  cleanup_macos_editor() {
    status=$?
    if [[ "$status" -ne 0 ]]; then
      if [[ -n "$candidate_id" && -e "$app" && "$(macos_bundle_identity "$app")" == "$candidate_id" ]]; then
        macos_rename_bundle "$app" "$build/failed.app" "$candidate_id" || true
      fi
      if [[ -e "$build/previous.app" ]]; then
        macos_rename_bundle "$build/previous.app" "$app" "$previous_id" || true
      fi
    fi
    # Keep the backup if restoring it failed; never delete the only old copy.
    if [[ "$status" == 0 || ! -e "$build/previous.app" ]]; then
      rm -rf -- "$build"
    else
      printf 'Named editor recovery incomplete; previous components preserved at %s.\n' "$build" >&2
    fi
    return "$status"
  }
  trap cleanup_macos_editor EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  candidate="$build/VS Code - $name.app"
  /bin/cp -cR "$source_app" "$candidate" || die "could not copy the VS Code application"
  /usr/bin/codesign --verify --deep --strict "$candidate" || die "the copied VS Code signature did not verify"
  [[ -x "$candidate/Contents/Resources/app/bin/code" ||
    -x "$candidate/Contents/Resources/app/bin/code-insiders" ]] || die "the copied VS Code CLI is missing"
  [[ "$(macos_vscode_source_metadata "$source_app" "$executable")" == "$metadata" ]] ||
    die "VS Code changed while its named copy was being prepared; try again"
  printf '%s\n' "$metadata" >"$build/source" || die "could not record the source editor metadata"
  if [[ -d "$app" ]] && macos_vscode_is_running "$home/vscode-user-data"; then
    printf 'VS Code update pending for %s; its editor started during preparation. Reopen after quitting to refresh.\n' "$name" >&2
    printf '%s\n' "$app"
    exit 0
  fi
  # Establish ownership before the first install. A crash before the metadata
  # commit leaves a recognized incomplete cache that can be rebuilt safely.
  if [[ ! -e "$marker" ]]; then
    printf 'codex-contexts-vscode-editor-v1\npending\n' >"$build/pending" || die "could not prepare the editor ownership marker"
    mv "$build/pending" "$marker" || die "could not install the editor ownership marker"
  fi
  candidate_id="$(macos_bundle_identity "$candidate")" || die "could not identify the copied named editor"
  if [[ -n "$previous_id" ]]; then
    macos_rename_bundle "$app" "$build/previous.app" "$previous_id" || die "could not stage the previous named editor"
  fi
  if ! macos_rename_bundle "$candidate" "$app" "$candidate_id"; then
    die "could not install the named VS Code editor"
  fi
  mv "$build/source" "$marker" || die "could not commit the named editor source metadata"
  printf '%s\n' "$app"
)

