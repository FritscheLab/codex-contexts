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

The installer writes `~/Applications/Codex Project.app` and
`~/Library/Services/Open in Codex Project.workflow` and registers the integration.
It builds and signs the app locally from the checked-out scripts. Review that
checkout first and run the installer as your own user.
[Installation prerequisites](../INSTALLATION.md#1-install-prerequisites) | [Review the checkout](../INSTALLATION.md#review-the-checkout-before-running-it)

```bash
./bin/install-macos-open-with
```

The app bundles the helper and Python configuration reader. Reinstall after
reviewing an update to refresh the bundled code. The installer refuses
unrelated namesake apps or workflows. [Update the repository](../INSTALLATION.md#updating-this-repository)

Use your normal account; default destinations need no administrator rights.
`CODEX_MACOS_APP_DIR` and `CODEX_MACOS_SERVICES_DIR` override the destinations.
Use the same values for reinstall, cleanup, and uninstall. Keep the defaults
for normal Finder discovery; custom directories must be writable by you.
Destination directories must be owned by you and not writable by other users.
Installers sharing a destination wait for one another; keep their hidden
`.codex-contexts-*.lock` files in place.
`CODEX_MACOS_SKIP_REGISTER=1` suppresses registration and Services refresh for
isolated tests.

Finder runs the helper through a noninteractive zsh login shell. If `direnv`
or `python3` is available in your terminal but missing in Finder, check the
login-shell `PATH`. Put any needed Homebrew setup and absolute
`CODEX_HOMES_ROOT` override in `~/.zprofile` or the corresponding zsh login file.
Run this from Terminal to check what the login shell can see.

```bash
/bin/zsh -lc 'command -v direnv
command -v python3
printf "%s\n" "${CODEX_HOMES_ROOT:-$HOME/.codex-homes}"'
```

The default install adds one **Codex Project** folder handler. For a file
manager such as ForkLift that offers folder **Open With**, explicitly create
an identity handler with `./bin/codex-home vscode-open-with NAME`.
Normal launches and reinstalls do not recreate those per-identity handlers.
Keep Finder as the default folder handler; do not choose **Change All**.

## Use it

1. Right-click the project folder itself in Finder.
2. Choose **Quick Actions > Open in Codex Project**, or **Services > Open in
   Codex Project**. **Finder > Services** also works for a selected folder.
3. Choose an identity for a new folder. An untouched generated context offers
   open, change, remove, and **Review and approve existing Codex context...**.
   If the folder has a custom `.envrc` or needs repair, choose **Get setup
   instructions...** for manual setup or rename recovery.

Setup and change generate local project files and offer **Review in VS Code**.
Inspect the read-only `.envrc` snapshot and close its window to continue. The
default is **Leave Unapproved**. **Approve & Open** lets direnv run `.envrc`
with your user permissions now and on future loads, then starts VS Code.
The helper fingerprints the generated `.envrc` and workspace and checks those
files before and after approval. Review their contents and any code they point
to. [What approval allows](security.md#what-an-approval-allows)

To resume paused setup, choose **Review and approve existing Codex context...**
or approve from the terminal after reviewing both files. [Project setup](projects-vscode.md)
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

From the clone, run the preview and read every `Would remove` path.

```bash
./bin/cleanup-macos-open-with
```

Full cleanup checks installer backup locations, owned handlers in
`~/Applications`, and named editor copies under `~/.codex` and the named
identity homes. For installer backups alone, add `--backups-only` to both
commands. If paths or running editors change, preview again with the same
options and directories you intend to use for removal.

**`--apply` scans again and permanently deletes eligible bundles and backups.**
It unregisters apps as needed and deletes the bundles directly, outside Trash.
Copy any backups you want to keep before running it. Running editors are reported
and skipped. The main Codex Project app and Quick Action are managed by uninstall.

```bash
./bin/cleanup-macos-open-with --apply
```

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
| Helper finds different identities or dependencies in Finder | Check the zsh login environment described under [installation](#install-the-finder-integration). |
| Launch refused | Check the reported identity, direnv approval, generated workspace, and availability of direnv/VS Code using the [project launch checks](projects-vscode.md#launch-checks). The app stops instead of silently selecting `default`. |

To distinguish menu discovery from an app failure, open the installed app
against a folder directly:

```bash
open -a "$HOME/Applications/Codex Project.app" -- "/path/to/project"
```

## Uninstall the Finder integration

This command unregisters and moves the owned **Codex Project.app**, its Quick
Action, and recognized identity handlers in the selected app directory to Trash
as soon as it runs. Check the app and Services directories, using the same
destination overrides you used for installation, before invoking it.

```bash
./bin/uninstall-macos-open-with
```

Use `--help` to see usage for either the installer or uninstaller.

The uninstaller refuses unrelated namesakes. It can still remove an orphaned
Quick Action.
Named editor copies, identity state, project files, the repository, and
installed dependencies remain. Use [cleanup](#clean-up-generated-apps) for
copies, or the [folder removal guide](remove-folder-context.md) for project
settings.

A project generated by the bundled helper records the app's Resources path in
`PATH_add`. After uninstalling, reset or regenerate that context using a
stable repository clone; its old helper path is stale. Reinstall to restore
Finder integration, and use the repository helper for launches meanwhile.

## Installation recovery

If installation reports a recovery directory, inspect it for the prior app
or Quick Action before retrying. [Preview backup cleanup](#clean-up-generated-apps)

Apple documents [Quick Actions in Finder](https://support.apple.com/guide/mac-help/mchl97ff9142/mac)
and [Automator Quick Actions](https://support.apple.com/guide/automator/aut7cac58839/mac).
