# Finder “Open in Codex Project” Quick Action

Use **Open in Codex Project** to open a folder in VS Code with its selected
Codex identity. The Quick Action passes folders to `Codex Project.app`, which
checks `direnv` approval and can set up, change, or remove a folder's context.

Ordinary Finder launches of VS Code do not evaluate the folder's `.envrc`.
They inherit the GUI environment, so Codex usually falls back to `~/.codex`.

| Task | Start here |
|---|---|
| Add or update the app and Quick Action | [Install the Finder integration](#install-the-finder-integration) |
| Open a folder or choose its identity | [Use it](#use-it) |
| Find a missing Quick Action | [Check Finder's menus](#if-open-in-codex-project-is-not-listed) |
| Stop a folder from selecting an identity | [Remove Codex settings from a folder](remove-folder-context.md) |
| Remove one or all **VS Code - NAME** menu entries | [Clean up Open With](#remove-extra-vs-code-entries-from-open-with-on-macos) |
| Remove the app, Quick Action, and generated menu entries | [Uninstall the Finder integration](#uninstall-the-finder-integration) |

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

The installer also creates **VS Code - NAME** handlers in `~/Applications`
for file managers with folder **Open With** menus, such as ForkLift. The helper
opens a named VS Code instance for each identity and reuses it while running.
Hover over its Dock icon to read the identity; click it to focus the editor.
See [macOS Dock names](projects-vscode.md#macos-dock-names) for labels, copy
refresh, and the original-editor option. Do not pin or directly launch the
editor copies under an identity home; they need the helper's environment
and launch arguments.

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
Project**. If the action is missing, [check Finder's menus](#if-open-in-codex-project-is-not-listed).

In file managers with folder **Open With** menus, choose **VS Code - NAME**
to open an already configured project directly. Its approved `.envrc` must
select that identity, and its generated workspace must exist. The handler
reports an identity mismatch rather than opening a different account. It
passes the folder to `codex-home`, which opens the workspace in the named
VS Code instance. Do not choose **Change All**; keep Finder as the default
handler for folders.

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
or unrecognized files, follow
[manual removal](remove-folder-context.md#remove-the-settings-manually), or
review the [Codex environment block](projects-vscode.md#existing-envrc) to
change identities in a custom setup.

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

## If removing a folder's context fails

If **Remove Codex context from this folder…** fails, use
[Remove Codex settings from a folder](remove-folder-context.md):

- [Try removal from Terminal](remove-folder-context.md#try-removal-from-terminal) if the menu cannot run the helper.
- [Remove the settings manually](remove-folder-context.md#remove-the-settings-manually) if removal is refused or files are edited or missing.

If `.envrc` is already missing, the app offers setup instead of removal; use
the manual route to inspect any remaining workspace settings.

Keep the project folder and your identity homes. Uninstalling the Finder app
does not remove a folder's `.envrc` or workspace settings.

## Remove extra VS Code entries from Open With on macOS

To clean up **VS Code - default**, **VS Code - work**, and similar items in the
right-click **Open With** menu, remove their generated launcher apps from
`~/Applications`. Your accounts, projects, and VS Code settings are kept.
Keep **Visual Studio Code**, the original editor.

Choose the cleanup you want; you only need to follow one route:

| Remove… | Start here |
|---|---|
| One unwanted VS Code entry | [Remove one entry](#remove-one-entry) |
| Every generated VS Code entry, keeping **Open in Codex Project** | [Remove all VS Code entries](#remove-all-generated-vs-code-entries-keeping-the-quick-action) |
| VS Code entries **and** the Codex Project app and Quick Action | [Uninstall the Finder integration](#uninstall-the-finder-integration) |

**Before you start:** normal project launches can recreate these entries.
To keep the menu clear afterward, use the
[terminal launch option below](#prevent-removed-entries-from-returning).
The one-entry and all-entry steps can be run from any Terminal directory.

### Remove one entry

1. **Find the launcher.** In Finder, choose **Go > Go to Folder…**
   (`Shift-Command-G`), enter `~/Applications`, and select the unwanted app,
   such as `VS Code - default.app`. Leave it there for the next step.
   If it is missing, go to [If an entry remains visible](#if-an-entry-remains-visible).

2. **Clear its menu registration.** Open Terminal and paste the following
   block. Replace `default` with the name on the app you selected, then press
   Return. This step leaves the app in place.

   ```bash
   LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
   "$LSREGISTER" -u "$HOME/Applications/VS Code - default.app"
   ```

   No output is normal. If Terminal reports a missing path, compare the name
   with the app in Finder and correct it before continuing.

3. **Move that launcher to Trash.** Return to Finder and choose
   **File > Move to Trash** for the same app. This prevents macOS from finding
   it again at that location. If macOS says it is in use, save your work and
   quit that identity's VS Code, then try again.

4. **Check the menu.** Reopen the project's **Open With** menu. The selected
   entry should be gone; your other entries should remain. If it is still
   listed, follow [the refresh steps below](#if-an-entry-remains-visible).

To undo this cleanup, [restore the entry](#restore-a-removed-entry).

### Remove all generated VS Code entries, keeping the Quick Action

These steps keep **Open in Codex Project** available in Finder.

1. **Clear the generated menu registrations.** Open Terminal, paste this
   entire block, and press Return. It prints the apps it finds and clears
   their registrations. It leaves the apps in place and skips apps that were
   not created by this helper, even if their names are similar.

   ```bash
   LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
   find "$HOME/Applications" -maxdepth 1 -type d -name 'VS Code - *.app' -print0 |
   while IFS= read -r -d '' app; do
     marker="$app/Contents/Resources/codex-contexts-open-with"
     [ -f "$marker" ] || continue
     [ "$(sed -n '1p' "$marker")" = 'codex-contexts-vscode-open-with-v1' ] || continue
     printf '%s\n' "$app"
     "$LSREGISTER" -u "$app"
   done
   ```

   If the command finishes without errors and prints no paths, it found no
   matching launchers. If the folder is missing or unwanted entries are still
   visible, use [the recovery steps below](#if-an-entry-remains-visible).

2. **Move the listed launchers to Trash.** In Finder, choose
   **Go > Go to Folder…** (`Shift-Command-G`) and enter `~/Applications`.
   Hold Command while selecting the apps listed in Terminal, then choose
   **File > Move to Trash**. Keep `Codex Project.app` and `Visual Studio Code.app`.
   If an app is in use, save your work and quit its VS Code instance before
   trying again.

3. **Check the menu.** Reopen **Open With**. The generated **VS Code - NAME**
   entries should be gone, while **Open in Codex Project** remains available
   under Finder's **Quick Actions** or **Services**. If an entry remains,
   follow [the refresh steps below](#if-an-entry-remains-visible).

These launchers always live in `~/Applications`, even if you installed
`Codex Project.app` elsewhere. You can [restore an entry](#restore-a-removed-entry)
if you change your mind; there is no need to empty Trash to check the result.

### If an entry remains visible

1. Close and reopen the menu. If you use another file manager, quit and reopen
   that app. If needed, log out and back in.
2. If the entry disappeared but returned after opening a project, follow
   [Prevent removed entries from returning](#prevent-removed-entries-from-returning).
3. If it never disappeared and its launcher is already gone from
   `~/Applications`, check for an older editor copy as described below.

**Older editor copies:** in Finder's **Go to Folder…**, open
`~/.codex/vscode-editor` for `default`, or `~/.codex-homes/NAME/vscode-editor`
for another identity. Replace `NAME` with your identity; if you configured a
custom `CODEX_HOMES_ROOT`, use that location instead of `~/.codex-homes`.
If there is no copy there, skip this cleanup rather than guessing another path.

If you find an unwanted copy, save your work and quit that identity's editor.
Clear its registration using its exact path, for example:

```bash
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
"$LSREGISTER" -u "$HOME/.codex/vscode-editor/VS Code - default.app"
```

Move only that `.app` to Trash, then reopen the menu. Keep the identity home
and `vscode-user-data` directory. Repeat for other unwanted copies if needed.
Avoid a global Launch Services database reset; it also affects unrelated apps.

### Prevent removed entries from returning

**Use Terminal to open projects if you want these entries to stay removed.**
Normal `codex-home vscode` / `vscode-project` launches, the Finder Quick Action,
and reinstalling the integration can recreate them.

After the cleanup, quit that identity's editor. From your repository directory,
run the command below, replacing `work` and the project path with your own:

```bash
CODEX_MACOS_SKIP_REGISTER=1 CODEX_VSCODE_DOCK_LABEL=0 \
  ./bin/codex-home vscode work "/path/to/project"
```

This opens your isolated project in the original VS Code app without creating
the extra launchers or named editor copies. Recheck **Open With** after launch.
Use both settings each time; `CODEX_VSCODE_DOCK_LABEL=0` alone does not stop
launcher creation. For subsequent terminal launches, you can export both
variables in your calling shell's startup file.

### Restore a removed entry

From the repository directory, run this command, replacing `default` with the
identity you want back:

```bash
CODEX_MACOS_SKIP_REGISTER=0 ./bin/codex-home vscode-open-with default
```

This restores the launcher even if you use the terminal launch settings above.
Reopen **Open With** to check that the entry is available again.
If you removed the entire Finder integration,
[reinstall it](#install-the-finder-integration).

For the Finder steps, see Apple's
[app removal instructions](https://support.apple.com/en-us/102610).

## Uninstall the Finder integration

The uninstaller removes **Codex Project.app**, **Open in Codex Project**, and
all generated **VS Code - NAME** launchers. If you used custom installation
paths or the app's bundled helper, read the notes below before running it.

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

The uninstaller unregisters the exact active app path and moves the app bundle,
owned Quick Action, and generated identity handlers to Trash. It also removes
the Quick Action if the app is already absent, and refuses to remove an unrelated workflow with the same
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

VS Code user data remains intact, as do named editor copies in `vscode-editor`.
After uninstalling, use the repository's `codex-home` to open projects with
their approved context; do not open a named editor copy directly.

Reopen your file manager's menu to check the result. If an entry remains,
follow [If an entry remains visible](#if-an-entry-remains-visible).
To undo removal, [reinstall the Finder integration](#install-the-finder-integration).

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
Codex Project and the identity-specific VS Code handlers declare folder support using
[LSItemContentTypes](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundledocumenttypes/lsitemcontenttypes)
for systems and dialogs that offer **Open With**.
