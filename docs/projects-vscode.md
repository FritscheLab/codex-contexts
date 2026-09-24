# Projects, direnv, and VS Code

A **project context** selects the identity for a folder. Its `.envrc` points
to that identity's **home** (`CODEX_HOME`), so the terminal and a helper-launched
VS Code window use the same configuration.

Start with [Installation steps 1–3](../INSTALLATION.md#1-install-prerequisites)
and a [verified identity](commands.md#check-the-selected-identity).
Run `./bin/codex-home` examples from the clone directory. Bare `codex-home`
works once the helper is on `PATH`, including inside an approved generated
project with the `direnv` shell hook enabled.

- New project context: [generate and approve the files](#generate-project-files),
  then [run in the terminal](#run-from-the-terminal) or [open VS Code](#launch-an-isolated-window).
- Existing setup: [merge an `.envrc`](#existing-envrc), [merge workspace settings](#existing-vs-code-workspace),
  or [change the selected identity](#change-or-remove-a-folders-codex-context).
- Remove the setup: [Remove Codex settings from a folder](remove-folder-context.md)
  also covers a failed context-menu action.

## Generate project files

Replace `work` with your existing identity and `/path/to/project` with your project path.

```bash
./bin/codex-home project work "/path/to/project"
```

Keep the command on one shell line. Quote paths containing spaces.

The generated `.envrc`:

- exports `CODEX_IDENTITY` and `CODEX_HOME`;
- checks that the selected home exists;
- loads `$CODEX_HOME/.env` when present;
- adds the directory containing the helper to `PATH` (the repository's `bin`
  directory or the installed app's `Contents/Resources` directory);
- watches the identity config and key file;
- prints the active identity whenever `direnv` reloads.

The generated `.vscode/<folder-name>.code-workspace` uses the project folder's
name in the Explorer, shows `<folder-name> [CODEX: IDENTITY]` in the title,
and sets a status-bar color.

Review both files before use. They contain no credentials when generated, but
`.envrc` is executable shell code with local paths and an identity name. The
workspace also includes that name. Keep these files local to your computer.

You can open a read-only `.envrc` review in VS Code with
`./bin/codex-home project-review "/path/to/project"`, or use a text editor.
After reviewing both files, approve `.envrc`:

```bash
direnv allow "/path/to/project"
```

Then [run from the terminal](#run-from-the-terminal) or
[open VS Code](#launch-an-isolated-window).

## Run from the terminal

With the [direnv shell hook](../INSTALLATION.md#2-enable-direnv-in-your-shell)
enabled and the project's `.envrc` approved:

```bash
cd "/path/to/project"
codex-home run
```

The helper uses `CODEX_IDENTITY`, which `direnv` sets when you enter the
project. If no context is active, enter a configured project or use
`codex-home run work` to select an identity explicitly. An explicit identity
works without `direnv` and overrides the project selection for that launch.

Options work directly. Put `--` before a prompt or subcommand so it is not
read as an identity name:

```bash
codex-home run --model MODEL
codex-home run -- resume --last
codex-home run -- "Explain this project"
```

The identity name stays in the terminal title while Codex runs; see
[terminal context labels](#terminal-context-labels) for title settings and
recovery. Follow the [CLI identity checks](commands.md#check-the-selected-identity)
before using a newly selected identity.

## Launch an isolated window

Open the approved project with its selected identity:

```bash
./bin/codex-home vscode-project "/path/to/project"
```

To also check that the project selects `work`, name the expected identity:

```bash
./bin/codex-home vscode work "/path/to/project"
```

The launcher loads the approved `direnv` environment once, verifies the identity
and its home, then starts VS Code in that same environment with:

```text
--new-window
--user-data-dir ~/.codex-homes/work/vscode-user-data
--extensions-dir ~/.vscode/extensions
```

Ordinary new windows can reuse a running VS Code process and its environment.
A separate `--user-data-dir` starts an instance with the intended identity;
`--new-window` alone does not do that.

The launcher reuses the shared extensions directory when it exists, avoiding
a separate Codex extension installation for each identity. To use custom paths:

```bash
export CODEX_VSCODE_CLI="/custom/path/to/code"
export CODEX_VSCODE_EXTENSIONS_DIR="$HOME/.vscode/extensions"
```

Set editor overrides and `CODEX_HOMES_ROOT` in the calling shell, not in the
project's `.envrc`. The launcher selects these settings before loading the
project environment.

On macOS the helper also checks standard application locations, so installing
the `code` shell command is convenient but not mandatory.

## Verify inside the window

Start a new Codex chat, then follow the [VS Code identity checks](commands.md#check-the-selected-identity).
They compare the project selection with the extension's account or API-key
status and selected model. The window label alone cannot verify the account.

## Keep project files local

If the project is already in Git, `codex-home project` adds patterns to
`.git/info/exclude`. For a repository folder named `project`, they are:

```gitignore
/.envrc
/.vscode/project.code-workspace
```

For a project below the repository root, the patterns include that relative
directory. `.git/info/exclude` is local repository metadata, so the exclusion
itself is not committed or shared. The command also refuses to recreate either
path if Git already tracks it.

If the directory is not yet a Git repository, no exclusion is added. If Git is
initialized later, add equivalent patterns to the new repository's
`.git/info/exclude` before staging files.

To share either file through Git, agree with your team on paths and identity
names that work for everyone, then remove its local exclude pattern. Review
each `.envrc` change before approving it. Check how the project uses any
existing workspace before replacing it.

## Existing `.envrc`

The helper refuses to overwrite an existing `.envrc`. Add this block manually,
using your identity's name and path:

```bash
export CODEX_IDENTITY="work"
export CODEX_HOME="$HOME/.codex-homes/work"

if [[ ! -d "$CODEX_HOME" ]]; then
  log_error "Missing Codex identity directory: $CODEX_HOME"
  return 1
fi

dotenv_if_exists "$CODEX_HOME/.env"
watch_file "$CODEX_HOME/config.toml"
if [[ -f "$CODEX_HOME/.env" ]]; then
  watch_file "$CODEX_HOME/.env"
fi
```

Then run `direnv allow` again.

If a committed `.envrc` came from another computer, do not approve it until you
have read the shell code and replaced paths that do not belong to your machine.

## Existing VS Code workspace

The helper also refuses to replace an existing
`.vscode/<folder-name>.code-workspace`. If you already use a workspace, merge
the title and color settings into it. For a folder named `my-project`:

```json
{
  "settings": {
    "window.title": "my-project [CODEX: WORK]",
    "workbench.colorCustomizations": {
      "statusBar.background": "#1F883D",
      "statusBar.foreground": "#FFFFFF"
    }
  }
}
```

The label helps you recognize the account. The process environment determines
which identity Codex uses; changing the label alone does not change accounts.

## Change or remove a folder's Codex context

For removal, go directly to [Remove Codex settings from a folder](remove-folder-context.md).
To switch the folder to another identity, continue below.

Close the folder's isolated VS Code window before changing its identity. An
already-running shell, VS Code process, or Codex chat keeps its old environment
and identity until it is closed or reloaded.

For untouched files created by `codex-home`, change the identity with:

```bash
./bin/codex-home project-change NEW_IDENTITY "/path/to/project"
```

The command verifies that `.envrc` and the generated workspace are untracked
regular files that exactly match a recognized template. It then revokes the
existing `direnv` approval, replaces both files, and leaves `.envrc` unapproved.
If either replacement fails, it attempts to restore the original files. If
restoration also fails, it retains backups and reports their location. Review
`.envrc` before continuing:

```bash
direnv allow "/path/to/project"
./bin/codex-home vscode-project "/path/to/project"
```

### Manual recovery for a custom or shared setup

If **Remove Codex context from this folder…** or `project-reset` fails, go to
[Remove the settings manually](remove-folder-context.md#remove-the-settings-manually).
The four steps cover backing up files, revoking approval, removing only the
Codex settings, and checking a fresh session. They preserve your project tools,
custom VS Code settings, and identity homes.

For a custom setup you want to keep, first
[back up and inspect its files](remove-folder-context.md#1-find-and-back-up-the-affected-files)
and [revoke the existing approval](remove-folder-context.md#2-stop-loading-the-old-environment).
Update only the [identity block](#existing-envrc) and the corresponding
[workspace labels](#existing-vs-code-workspace), preserving unrelated commands
and settings. Review the edited `.envrc`, approve it with `direnv allow`, and
start a fresh editor session. A workspace migration can retain those settings
in the [folder-named workspace](#generate-project-files); inspect existing files
before renaming anything or changing local Git exclusions.

## Switching identities

A running Codex chat keeps its account when you change terminal directories.
Open the new identity's workspace with `codex-home vscode`, then start a new
chat.

Codex's account menu signs out of the current home; it cannot select another
saved `CODEX_HOME`. VS Code Profiles separate editor settings but still share
a process environment, so use the helper to switch identities.

## Migrate a generated workspace

For a project using `.vscode/codex-context.code-workspace`, run
`project-change` with the identity already selected for that project:

```bash
./bin/codex-home project-change NAME "/path/to/project"
```

For untouched generated files, this replaces the generic workspace with
`.vscode/<folder-name>.code-workspace` and updates its local Git exclusions.
Review the generated `.envrc` and run `direnv allow` before reopening the
project. From Finder, choose **Set or change Codex identity…** and select the
same identity to perform this migration.

For modified or shared files, use
[manual recovery](#manual-recovery-for-a-custom-or-shared-setup). For duplicate
Finder entries or Dock items pointing into `vscode-dock`, see
[launcher recovery](macos-open-with.md#replace-obsolete-launcher-entries).

## Terminal context labels

In an interactive terminal, `codex-home run` displays **[CODEX: NAME]** at
launch and keeps it in the tab/window title while Codex runs. It clears the
label on exit and restores the previous title when the terminal supports a
title stack.

Running `codex` directly uses its own title settings, even inside a `direnv`
project. The helper labels the terminal title, not Codex's footer. It uses a
launch-only `tui.terminal_title=[]` override to keep Codex from replacing the
title, leaving saved settings alone. It skips terminal controls when streams
are redirected or `TERM=dumb`.

If the label is hidden, check your terminal's title settings. In iTerm2, allow
applications to change the title and include the session name in the title.
See [iTerm2 session titles](https://iterm2.com/documentation-session-title.html),
[Terminal window titles](https://support.apple.com/guide/terminal/trml15228/mac),
and [Codex TUI settings](https://learn.chatgpt.com/docs/config-file/config-sample).

U-M launches also check the [identity's model scope](umgpt.md#guardrail-boundaries).
The broader `umgpt-low` scope prints **LOW-SENSITIVITY DATA ONLY**. These local
checks do not establish institutional approval; follow the
[U-M data guidance](umgpt.md#check-data-permissions-first) before use.

## macOS Dock names

For standard VS Code and VS Code Insiders on macOS, the helper prepares a
complete application copy named `VS Code - work` (or your selected identity).
The `default` identity uses `VS Code - default`. Its location is:

```text
$CODEX_HOME/vscode-editor/VS Code - NAME.app
```

The helper launches that application's own `code` CLI with the approved
project environment and identity-specific `--user-data-dir`. The CLI handles
both startup and requests for an already-running identity. The copied app's
contents and vendor signature remain unchanged; its directory supplies the
identity name. On APFS, copy-on-write cloning shares unchanged file data with
the source application. Where cloning is unavailable, macOS makes a normal
copy, which can use a full application's worth of storage per identity. The
original VS Code installation remains available for ordinary use.

On macOS, the Finder integration creates a small handler app at
`~/Applications/VS Code - NAME.app` for each configured identity. File managers
that expose folder handlers in an **Open With** menu, such as ForkLift, can use
it to forward the folder to `codex-home vscode NAME`. In Finder, use **Quick
Actions > Open in Codex Project** or **Services > Open in Codex Project**; that
app reads the folder's current context. The actual editor copy remains under
`CODEX_HOME/vscode-editor` and keeps its separate Dock name.

Hover over a running editor's Dock icon to read its identity. Clicking that
running icon focuses the editor. The icon artwork remains VS Code's, while
the workspace title and status-bar color also identify the selected context.

**After quitting, start the identity through the Finder Quick Action, a
file-manager Open With handler, or `codex-home`.** Do not pin or directly open
the generated editor copies: macOS launches them without the helper's
`CODEX_HOME`, approved environment, or `--user-data-dir` arguments.

Update the original VS Code installation and let the helper refresh its
copies; avoid updating individual identity copies separately. Refresh occurs
when that identity is stopped. If its editor is running, quit it and reopen
the project through the helper or Finder Quick Action. Check the window titles
so you close only the intended identity. Reinstall Codex Project after updating
the helper.

Custom `CODEX_VSCODE_CLI` wrappers and Linux use the supplied CLI. To use the
original installed application's CLI without a named copy on macOS:

```bash
CODEX_VSCODE_DOCK_LABEL=0 ./bin/codex-home vscode work "/path/to/project"
```

This override changes how helper launches select the editor; it does not
rename an already-running instance. Quit that identity before switching launch
modes. Its workspace title, status color, and isolated user data are retained.

To remove individual or all generated **Open With** entries, see
[Remove extra VS Code entries from Open With](macos-open-with.md#remove-extra-vs-code-entries-from-open-with-on-macos),
including how to stop terminal launches from recreating them.

## Open from Finder (macOS only)

The optional Finder Quick Action opens the app, which loads the project's
approved `direnv` settings before opening VS Code. Right-click a folder and
choose **Quick Actions > Open in Codex Project** (or **Services**). See
[Finder integration](macos-open-with.md).

## Remote SSH and dev containers

This helper is designed for local VS Code and local identity homes. In Remote
SSH, WSL, or a dev container, the Codex extension and terminal may run on the
remote side where the host's paths do not exist. Install the helper and create
identity homes in that execution environment; never copy credentials into a
repository or container image.

Reference: [VS Code isolated instances](https://code.visualstudio.com/docs/configure/command-line#_isolating-vs-code-instances).
