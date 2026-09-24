# Finder “Open in Codex Project” Quick Action

Opening a folder with ordinary VS Code from Finder does not evaluate that
folder's `.envrc`. VS Code therefore inherits the GUI environment and Codex
usually falls back to `~/.codex`.

Install the **Open in Codex Project** Quick Action to open a folder with its
selected identity from Finder's context menu. It passes the selected folders
to `Codex Project.app`, which can also set up, change, or remove a folder's
Codex context. The app checks `direnv` approval before launching VS Code.

## Install the Finder integration

From this repository:

```bash
./bin/install-macos-open-with
```

The installer creates and registers:

```text
~/Applications/Codex Project.app
~/Library/Services/Open in Codex Project.workflow
```

Rerun the installer after updating the helper. It preserves the installed app
and Quick Action as [backups](#installation-backups), and refuses to replace an
unrelated Quick Action with the same name. The app contains the helper and no
credentials.

The bundled helper opens a named copy of VS Code for each identity, such as
`VS Code - work` or `VS Code - default`. Hover over its running Dock icon to
read the identity, or click it to focus the editor. Projects using a running
identity are sent to that instance. After quitting, open a project through
this Quick Action again; do not pin or directly relaunch the generated editor
copy because it needs the helper's environment and launch arguments. See
[macOS Dock names](projects-vscode.md#macos-dock-names) for copy refresh and
the original-editor opt-out.

To choose another installation directory:

```bash
CODEX_MACOS_APP_DIR="/path/to/apps" ./bin/install-macos-open-with
```

`~/Applications` is recommended because Finder discovers applications there.
This default installation does not need administrator rights. A custom
directory must be writable by your user; use your normal account to run the
installer and uninstaller.

`CODEX_MACOS_SERVICES_DIR` overrides the workflow destination, which is useful
for isolated tests. Keep its default, `~/Library/Services`, for normal Finder
discovery. If you override either destination, use the same values when
reinstalling or uninstalling. `CODEX_MACOS_SKIP_REGISTER=1` skips both Launch
Services registration and the Services menu refresh for isolated tests.

## Use it

In Finder:

1. Right-click or Control-click the project folder itself.
2. Choose **Quick Actions**, or **Services** depending on macOS and the menu.
3. Choose **Open in Codex Project**.
4. For a configured folder, choose an action from the app's menu. For a new
   folder, choose an identity directly.

You can also select a folder and use **Finder > Services > Open in Codex
Project**. If **Open With > Codex Project** is available, it opens the same app;
folder context menus do not consistently offer that route. Do not choose
**Change All**; Finder should remain the normal default handler for folders.

When the folder has no `.envrc`, the app goes straight to identity selection.
When it is already configured, the menu offers:

- **Open with current Codex context**;
- **Set or change Codex identity…**; and
- **Remove Codex context from this folder…**.

**Open with current Codex context** is selected by default, so you can press
Return to open a configured folder.

Setup and change list only usable identities that already exist on this
computer. Choose an identity and confirm setup to generate the project files.

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
recognized `codex-home` template. For edited, shared, tracked, symlinked,
or unrecognized files, follow the manual instructions in
[Projects, direnv, and VS Code](projects-vscode.md#change-or-remove-a-folders-codex-context).

The terminal equivalents are:

```bash
./bin/codex-home vscode-project "/path/to/project"
./bin/codex-home project-change NEW_IDENTITY "/path/to/project"
./bin/codex-home project-reset "/path/to/project"
```

`vscode-project DIR` reads the identity from the project's approved `.envrc`.

## If Open in Codex Project is not listed

- Select a folder, wait a few seconds, and reopen its context menu. The action
  receives folders, so it does not apply to a file or empty Finder background.
- Check **Finder > Services > Open in Codex Project** as well as **Quick
  Actions** in the context menu.
- Enable **Open in Codex Project** under **System Settings > Keyboard >
  Keyboard Shortcuts > Services** if it is unchecked.
- Rerun the installer if either installed component is missing or the app moved.
- Log out and back in if the Services menu has not refreshed.

If the installer reports a registration or Services refresh warning, check
the app directly while diagnosing menu discovery:

```bash
open -a "$HOME/Applications/Codex Project.app" -- "/path/to/project"
```

## Error dialogs

The launcher shows an error instead of falling back to `~/.codex` when:

- an existing `.envrc` is unapproved, invalid, or has no `CODEX_IDENTITY`;
- the referenced identity home no longer exists;
- the generated workspace file is missing;
- change or removal encounters modified, shared, tracked, or symlinked files;
- `direnv` or VS Code cannot be found.

The app stops on these errors. It does not silently choose `default`, approve
an existing file, or overwrite a file it does not recognize.

## Uninstall the Finder integration

From this repository, run:

```bash
./bin/uninstall-macos-open-with
```

For an app installed in a custom directory, use the same setting used during
installation. Also pass `CODEX_MACOS_SERVICES_DIR` if you changed the workflow
destination:

```bash
CODEX_MACOS_APP_DIR="/path/to/apps" ./bin/uninstall-macos-open-with
```

The uninstaller unregisters the exact active app path and moves the app bundle
and owned Quick Action to Trash. It also removes the Quick Action if the app
is already absent, and refuses to remove an unrelated workflow with the same
name. It does not remove project `.envrc` files, workspaces, identities,
credentials, this repository, `direnv`, VS Code, or Codex. If you want to
remove a folder's generated context too, use **Remove Codex context from this
folder…** before uninstalling, or run `codex-home project-reset` from the
repository.

A folder configured by the bundled app records its Resources directory in
`PATH_add`. Uninstalling the app leaves that path stale. The identity exports
remain readable, but `codex-home` will no longer be supplied by that path;
reset the folder or regenerate it with the helper from a stable repository
clone.

The uninstaller leaves identity homes, VS Code user data, and named editor
copies under `vscode-editor` intact. After uninstalling the Finder integration,
use the repository's `codex-home` to open projects with their approved context;
do not open a named editor copy directly.

## Maintenance and recovery

### Installation backups

Reinstalling moves the installed app and owned Quick Action into
`.codex-project-backups` directories beside each component. The `.app.backup`
and `.workflow.backup` suffixes prevent them from appearing as active
launchers. Uninstalling leaves these backups available for recovery. Review
them with:

```bash
find "$HOME/Applications/.codex-project-backups" -maxdepth 1 \
  -type d -name '*.app.backup' -print
find "$HOME/Library/Services/.codex-project-backups" -maxdepth 1 \
  -type d -name '*.workflow.backup' -print
```

Move any exact backup you no longer need to Trash.

### Replace obsolete launcher entries

If a Dock item points into `$CODEX_HOME/vscode-dock/`, remove that item from
the Dock. These shell wrappers contain separate helper copies and can show
outdated errors such as `project selects '', not 'NAME'`. Reinstall the Finder
integration, quit the affected editor, and open the project through **Quick
Actions > Open in Codex Project**. Keep the identity home, credentials, and
VS Code user data.

App backups named `Codex Project.backup.*.app` in `~/Applications` can also
appear as duplicate Finder entries. List them before choosing any to remove:

```bash
find "$HOME/Applications" -maxdepth 1 \
  -type d -name 'Codex Project.backup.*.app' -print
```

For each app backup you choose to remove, unregister that exact path with
the `lsregister -u` command shown below, then move that exact bundle to Trash.
Do not reset the global Launch Services database.

```bash
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
"$LSREGISTER" -u "/exact/path/to/Codex Project.backup.TIMESTAMP.app"
```

If a removed entry remains visible briefly, reopen the Finder menu or log out
and back in.

For a generated project that uses `codex-context.code-workspace`, follow
[Migrate a generated workspace](projects-vscode.md#migrate-a-generated-workspace).

Apple documents Automator Quick Actions as available from Finder and Services;
see [Create a Quick Action workflow](https://support.apple.com/guide/automator/aut7cac58839/mac)
and [Perform quick actions in Finder](https://support.apple.com/guide/mac-help/mchl97ff9142/mac).
The app also declares folder support using
[LSItemContentTypes](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundledocumenttypes/lsitemcontenttypes)
for systems and dialogs that offer **Open With**.
