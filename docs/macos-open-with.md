# Finder “Open With Codex Project”

Opening a folder with ordinary VS Code from Finder does not evaluate that
folder's `.envrc`. VS Code therefore inherits the GUI environment and Codex
usually falls back to `~/.codex`.

Install `Codex Project.app` to open a folder with its selected identity. The
app can also set up, change, or remove a folder's Codex context. It checks
`direnv` approval before launching VS Code.

## Install the Finder app

From this repository:

```bash
./bin/install-macos-open-with
```

The installer creates and registers:

```text
~/Applications/Codex Project.app
```

The app contains a copy of `bin/codex-home` and no credentials. Rerun the
installer after updating the helper. It unregisters the previous app and moves
it into `.codex-project-backups` with an `.app.backup` suffix, so Finder does
not list duplicate launchers.

The installer builds the app with Apple's `osacompile`, signs it locally, and
registers it with Launch Services as a handler for `public.folder`.

To choose another installation directory:

```bash
CODEX_MACOS_APP_DIR="/path/to/apps" ./bin/install-macos-open-with
```

`~/Applications` is recommended because Finder discovers applications there.
This default installation does not need administrator rights. A custom
directory must be writable by your user; use your normal account to run the
installer and uninstaller.

## Use it

In Finder:

1. Control-click the project folder.
2. Choose **Open With**.
3. Choose **Codex Project**.
4. For a configured folder, choose an action from the app's menu. For a new
   folder, choose an identity directly.

Do not choose **Change All**; Finder should remain the normal default handler
for folders.

When the folder has no `.envrc`, the app goes straight to identity selection.
When it is already configured, the menu offers:

- **Open with current Codex context**;
- **Set or change Codex identity…**; and
- **Remove Codex context from this folder…**.

**Open with current Codex context** is selected by default, so you can press
Return to open a configured folder. The app activates before showing a dialog
when Finder launches it.

Setup and change list only usable identities that already exist on this
computer. Nothing is preselected. After you choose an identity, the app:

```text
Finder folder
  -> codex-home creates or replaces only recognized generated files
  -> the app summarizes the project, identity, and approval effect
  -> Review in VS Code opens an exact read-only .sh snapshot of .envrc
  -> closing the review window returns to the approval prompt
  -> Approve & Open runs direnv allow
  -> codex-home validates the selected identity
  -> VS Code starts with its identity-specific --user-data-dir
  -> Codex IDE extension reads the selected CODEX_HOME
```

Choose **Review in VS Code** to read the generated shell file. The app opens
an exact, read-only copy of `.envrc` with syntax highlighting. Close the review
window to return to the app; **Approve & Open** then becomes available. The
temporary copy is deleted when the review window closes.

**Leave Unapproved** keeps the generated files without authorizing them. You
can later use the menu's change/remove actions or approve the file manually:

```bash
direnv allow "/path/to/project"
```

Change and remove work only on untracked, regular files that still match a
current or older `codex-home` template. For edited, shared, tracked, symlinked,
or unrecognized files, follow the manual instructions in
[Projects, direnv, and VS Code](projects-vscode.md#change-or-remove-a-folders-codex-context)
for those cases.

After updating from a version that generated the generic
`codex-context.code-workspace` name, reinstall the Finder app and choose **Set
or change Codex identity…** for the folder. Selecting the same identity is
enough: it migrates the workspace to `<folder-name>.code-workspace`, then asks
you to review and reapprove the refreshed `.envrc`.

The terminal equivalents are:

```bash
./bin/codex-home vscode-project "/path/to/project"
./bin/codex-home project-change NEW_IDENTITY "/path/to/project"
./bin/codex-home project-reset "/path/to/project"
```

Unlike `vscode NAME DIR`, `vscode-project DIR` derives `NAME` from the
project's approved `.envrc`. This is the key step that a normal Finder launch
omits.

## If Codex Project is not listed

- Wait a few seconds and reopen the Finder context menu.
- Use **Open With > Other…**, browse to `~/Applications`, and select
  `Codex Project.app`.
- Launch the app once directly; it displays usage instructions.
- Rerun the installer if the app was moved or modified.
- Log out and back in if Launch Services has not refreshed its application
  list.

The installer warns rather than failing if immediate Launch Services
registration is unavailable; keeping the app in `~/Applications` lets Finder
discover it normally.

## Error dialogs

The launcher shows an error instead of falling back to `~/.codex` when:

- an existing `.envrc` is unapproved, invalid, or has no `CODEX_IDENTITY`;
- the referenced identity home no longer exists;
- the generated workspace file is missing;
- change or removal encounters modified, shared, tracked, or symlinked files;
- `direnv` or VS Code cannot be found.

The app stops on these errors. It does not silently choose `default`, approve
an existing file, or overwrite a file it does not recognize.

## Uninstall the Finder app

From this repository, run:

```bash
./bin/uninstall-macos-open-with
```

For an app installed in a custom directory, use the same setting used during
installation:

```bash
CODEX_MACOS_APP_DIR="/path/to/apps" ./bin/uninstall-macos-open-with
```

The uninstaller unregisters the exact active app path and moves the app bundle
to Trash. It does not remove project `.envrc` files, workspaces, identities,
credentials, this repository, `direnv`, VS Code, or Codex. If you want to
remove a folder's generated context too, use **Remove Codex context from this
folder…** before uninstalling, or run `codex-home project-reset` from the
repository.

A folder configured by the bundled app records its Resources directory in
`PATH_add`. Uninstalling the app leaves that path stale. The identity exports
remain readable, but `codex-home` will no longer be supplied by that path;
reset the folder or regenerate it with the helper from a stable repository
clone.

The installer preserves older launchers without credentials. Review current
backups with:

```bash
find "$HOME/Applications/.codex-project-backups" -maxdepth 1 \
  -type d -name '*.app.backup' -print
```

Move any exact backup you no longer need to Trash. Versions of the installer
before this change left `Codex Project.backup.*.app` directly in the
application directory. Those are complete application bundles and may still
appear in Finder. List them first:

```bash
find "$HOME/Applications" -maxdepth 1 \
  -type d -name 'Codex Project.backup.*.app' -print
```

For each legacy backup you choose to remove, unregister that exact path with
the `lsregister -u` command shown below, then move that exact bundle to Trash.
Do not reset the global Launch Services database.

```bash
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
"$LSREGISTER" -u "/exact/path/to/Codex Project.backup.TIMESTAMP.app"
```

If a removed entry remains visible briefly, reopen the Finder menu or log out
and back in.

Apple documents that applications declare supported document types using
`CFBundleDocumentTypes` and `LSItemContentTypes`; Finder's Open With menu uses
those Launch Services registrations. See Apple's
[LSItemContentTypes reference](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundledocumenttypes/lsitemcontenttypes)
and [Open With guide](https://support.apple.com/guide/mac-help/mh35597/mac).
