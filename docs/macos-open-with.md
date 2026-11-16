# macOS Finder and Dock integration

Use **Open in Codex Project** to open a folder with its selected identity.
The Quick Action calls `Codex Project.app`, which loads the approved project
context before launching VS Code. Ordinary Finder launches of VS Code do not
load `.envrc` and may use `~/.codex` instead.

| Task | Procedure |
|---|---|
| Add or update Finder integration | [Install](#install-the-finder-integration) |
| Open or configure a folder | [Use it](#use-it) |
| Give an identity a named Dock copy | [Optional named Dock copies](#optional-named-dock-copies) |
| Remove generated menu entries and old copies | [Cleanup](#clean-up-generated-apps) |
| Fix a missing menu or failed launch | [Finder and launch errors](#finder-and-launch-errors) |
| Remove a folder's context | [Folder removal guide](remove-folder-context.md) |
| Remove Finder integration | [Uninstall](#uninstall-the-finder-integration) |

## Install the Finder integration

After [installing prerequisites](../INSTALLATION.md#1-install-prerequisites), run
from the repository:

```bash
./bin/install-macos-open-with
```

This installs `~/Applications/Codex Project.app` and
`~/Library/Services/Open in Codex Project.workflow`. The app bundles the helper
and Python configuration reader, with no credentials. Rerun the installer
after [updating the repository](../INSTALLATION.md#updating-this-repository).
Existing unrelated namesake apps or workflows are refused.

Use your normal account; default destinations need no administrator rights.
`CODEX_MACOS_APP_DIR` and `CODEX_MACOS_SERVICES_DIR` override the destinations.
Use the same values for reinstall, cleanup, and uninstall. Keep the defaults
for normal Finder discovery; custom directories must be writable by you.
Destination directories must be owned by you and not writable by other users.
Installers sharing a destination wait for one another; keep their hidden
`.codex-contexts-*.lock` files in place.
`CODEX_MACOS_SKIP_REGISTER=1` suppresses registration and Services refresh for
isolated tests.

The default install adds one **Codex Project** folder handler. For a file
manager such as ForkLift that offers folder **Open With**, explicitly create
an identity handler with `./bin/codex-home vscode-open-with NAME`.
Normal launches and reinstalls do not recreate those per-identity handlers.
Keep Finder as the default folder handler; do not choose **Change All**.

## Use it

1. Right-click the project folder itself in Finder.
2. Choose **Quick Actions > Open in Codex Project**, or **Services > Open in
   Codex Project**. **Finder > Services** also works for a selected folder.
3. Choose an identity for a new folder. A configured folder offers **Open with
   current Codex context**, **Set or change Codex identity…**, and **Remove
   Codex context from this folder…**.

Setup and change offer existing usable identities. They generate local project
files, then require **Review in VS Code**. Inspect the read-only `.envrc`
snapshot and close its window to continue. **Leave Unapproved** is the default
at the separate approval step; choose **Approve & Open** only after review.
The helper checks the generated `.envrc` and workspace against their original
fingerprint before and after approval. Changed files cause refusal or
revocation. This detects changes; it does not isolate hostile processes
running as your user.

Leaving unapproved keeps the files without authorizing execution. See the
[project guide](projects-vscode.md) for later terminal setup and approval.
A **VS Code - NAME** handler uses the same review flow for an unconfigured
folder; an existing context must select `NAME`, or launch is refused.
Change and removal accept only untracked regular files matching a recognized
template. For custom changes, use [manual recovery](projects-vscode.md#manual-recovery-for-a-custom-or-shared-setup);
for deletion, use the [folder removal guide](remove-folder-context.md).

## Optional named Dock copies

The default uses the installed editor with separate VS Code user data for each
identity. The Finder Quick Action selects this mode explicitly. To request a
named application copy from the terminal:

```bash
CODEX_VSCODE_DOCK_LABEL=1 ./bin/codex-home vscode work "/path/to/project"
```

The copy lives at `$CODEX_HOME/vscode-editor/VS Code - NAME.app`. Its contents
and vendor signature remain unchanged. APFS cloning saves storage; other
volumes can require a full application copy per identity. Hover over the
running Dock icon to see its name; clicking it focuses that editor.

After quitting, reopen through `codex-home` with the option above. Do not pin
or directly launch generated copies: those launches lack the helper's
`CODEX_HOME`, approved environment, and `--user-data-dir` arguments. Quit that
identity before changing launch modes. Custom `CODEX_VSCODE_CLI` wrappers and
Linux use the supplied CLI.

Update the original VS Code installation, rather than individual copies. The
helper refreshes a copy when its identity is stopped; quit that editor and
reopen through the helper to refresh it. Leave `CODEX_VSCODE_DOCK_LABEL` unset
or `0` to return to the installed editor. Old Dock items pointing into
`$CODEX_HOME/vscode-dock/` are obsolete: remove the Dock item and reopen through
the helper, keeping credentials and VS Code user data.

## Clean up generated apps

Preview cleanup from the repository, inspect its exact paths, then apply:

```bash
./bin/cleanup-macos-open-with
./bin/cleanup-macos-open-with --apply
```

`--apply` unregisters and permanently deletes recognized identity handlers,
old installer backups, and stopped named editor copies. It keeps **Codex
Project**, its Quick Action, identity homes, credentials, chats, VS Code user
data, and project files. Unrelated apps and symlinks are skipped. Running
editors are reported and kept; quit the intended identity and rerun.
For installer backups alone, add `--backups-only` to preview and apply.
No permanent ZIP or application backups are created.

### Remove one entry

For a single unwanted launcher, locate its exact `.app` in `~/Applications`,
unregister that path, then move the same app to Trash in Finder:

```bash
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
"$LSREGISTER" -u "$HOME/Applications/VS Code - NAME.app"
```

Replace `NAME`; preserve the original **Visual Studio Code** application.
If the path is missing, inspect it before doing anything else. Quit the
identity's editor if the app is in use. To restore an identity handler later,
run `./bin/codex-home vscode-open-with NAME` explicitly.

### If an entry remains visible

Reopen the menu, restart the file manager, or log out and back in. If an entry
returns, reinstall the updated integration and keep named copies disabled.
The cleanup command covers recognized old copies under
`~/.codex/vscode-editor` and `~/.codex-homes/NAME/vscode-editor`; use your actual
`CODEX_HOMES_ROOT` when customized. For an unrecognized old copy, inspect its
exact path, unregister it as above, and move only that `.app` to Trash after
quitting the editor. Keep its identity home and `vscode-user-data`.
Avoid resetting the whole Launch Services database; it affects unrelated apps.

## Finder and launch errors

| Symptom | Check |
|---|---|
| Quick Action missing | Select a folder, not a file or empty background. Check both Quick Actions and Finder > Services. Enable the action in System Settings > Keyboard > Keyboard Shortcuts > Services. Reinstall if either component moved or is missing; log out and back in if needed. |
| `cannot read .../.envrc` or `Operation not permitted` | Inspect the named file and folder access. For protected folders, check **Codex Project** under macOS Privacy & Security; `direnv allow` does not fix an OS access denial. |
| Wrong or stale helper behavior | Reinstall after updating. Run `type -a codex-home` to locate older helper copies; see [updating](../INSTALLATION.md#updating-this-repository). |
| Launch refused | Check the reported identity, direnv approval, generated workspace, and availability of direnv/VS Code using the [project launch checks](projects-vscode.md#launch-checks). The app stops instead of silently selecting `default`. |

To distinguish menu discovery from an app failure, open the installed app
against a folder directly:

```bash
open -a "$HOME/Applications/Codex Project.app" -- "/path/to/project"
```

## Uninstall the Finder integration

From the repository, using the same custom destinations as installation:

```bash
./bin/uninstall-macos-open-with
```

This unregisters and moves owned **Codex Project.app**, its Quick Action, and
recognized identity handlers in the selected app directory to Trash.
Unrelated namesakes are refused. An orphaned Quick Action can still be removed.
Named editor copies, identity state, project files, the repository, and
installed dependencies remain. Use [cleanup](#clean-up-generated-apps) for
copies, or the [folder removal guide](remove-folder-context.md) for project
settings.

A project generated by the bundled helper records the app's Resources path in
`PATH_add`. After uninstalling, reset or regenerate that context using a
stable repository clone; its old helper path is stale. Reinstall to restore
Finder integration, and use the repository helper for launches meanwhile.

## Installation recovery

The installer stages previous components on their destination volumes, restores
them on failure, and deletes temporary copies after success. It refuses a
publication that cannot use an exclusive rename. If rollback cannot finish,
inspect the printed recovery directories before retrying; they contain the
prior components. Older persistent backups are handled by
[cleanup](#clean-up-generated-apps).

Apple documents [Quick Actions in Finder](https://support.apple.com/guide/mac-help/mchl97ff9142/mac)
and [Automator Quick Actions](https://support.apple.com/guide/automator/aut7cac58839/mac).
