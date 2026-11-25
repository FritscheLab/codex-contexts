# Projects, direnv, and VS Code

A project context selects an identity through `.envrc`. That identity's
`CODEX_HOME` holds its account, provider settings, and sessions. These commands
assume `codex-home` is on `PATH` and you have an identity. [Installation](../INSTALLATION.md)

For ePHI-restricted work, choose the project's helper launch and verify the
Toolkit route and model before sharing any ePHI. [Launch requirements](umgpt.md#check-data-permissions-first)

| Task | Go to |
|---|---|
| Configure the files yourself | [Manual setup](manual-setup.md) |
| Connect a new folder | [Generate project files](#generate-project-files) |
| Keep existing environment or editor settings | [Existing `.envrc`](#existing-envrc) / [workspace](#existing-vs-code-workspace) |
| Switch identities | [Change the context](#change-or-remove-a-folders-codex-context) |
| Disconnect a folder | [Remove its context](remove-folder-context.md) |

## Generate project files

Replace `work` and the quoted project path:

```bash
codex-home project work "/path/to/project"
```

| Generated file | Purpose |
|---|---|
| `.envrc` | Selects the identity, checks its home, adds the helper to PATH, and watches configuration/key changes. It does not export credentials. |
| `.vscode/<folder-name>.code-workspace` | Opens the folder with a `[CODEX: IDENTITY]` title and status-bar color. |

Read both files as text. `.envrc` runs as your user when direnv loads the
folder. Check the identity, home, helper path, and any files it loads. The
optional `project-review` command opens a read-only copy of a generated
`.envrc` and requests that VS Code disable extensions for the review. Review
the workspace file separately. Leave the file unapproved until you understand
what it runs.
[What approval allows](security.md#what-an-approval-allows)

```bash
direnv allow "/path/to/project"
```

Keep these machine-specific files local; see [Git exclusions](#keep-project-files-local).

## Run from the terminal

After approving `.envrc`, enter the project and check which identity it selects.

```bash
cd "/path/to/project"
direnv exec . codex-home current
direnv exec . codex-home run
```

With the direnv shell hook enabled, you can run `codex-home current` and
`codex-home run` directly. To select a named identity for one launch, use
`codex-home run work`. Implicit launches check the identity and home recorded
in a recognized generated destination, including a folder given with `-C` or
`--cd`. Use the helper to apply these checks. [Shell hook setup](../INSTALLATION.md#2-enable-direnv-in-your-shell)

Options pass through. Use `--` before a prompt or subcommand when omitting the
identity name:

```bash
codex-home run --model MODEL
codex-home run -- resume --last
codex-home run -- "Explain this project"
```

[Verify the selected account and model](commands.md#check-the-selected-identity).

<a id="launch-an-isolated-window"></a>
## Launch a separate VS Code window

The launch loads approved shell code, then opens VS Code with separate editor
state for the identity. Check any VS Code Workspace Trust prompt on its own.
Review project tasks, settings, and extensions before enabling them.
[Workspace Trust](https://code.visualstudio.com/docs/editing/workspaces/workspace-trust)

```bash
codex-home vscode-project "/path/to/project"
```

Use `codex-home vscode work "/path/to/project"` to also require that the
project selects `work`.

The helper evaluates the approved direnv context once, checks the identity and
home, and launches VS Code with filtered environment variables. New API
identities supply their key to Codex through a credential command, outside the
editor environment. [Opt in explicitly](security.md#environment-forwarding) to an SSH agent,
proxy, or external secret-manager variable.

Each identity uses `--user-data-dir <identity-home>/vscode-user-data` and
`--new-window`. It reuses `~/.vscode/extensions` when present. An ordinary VS
Code launch bypasses the helper's environment selection; `--new-window` alone
does not separate processes. Close existing windows for that identity before
changing its environment, and start a new Codex chat. The title alone does not
verify the account; follow the [IDE checks](commands.md#check-the-selected-identity).

Set overrides in the calling shell, before loading the project:

| Variable | Use |
|---|---|
| `CODEX_VSCODE_CLI` | Custom `code` command or executable path |
| `CODEX_VSCODE_EXTENSIONS_DIR` | Existing extensions directory to reuse |
| `CODEX_HOMES_ROOT` | Root containing the named identities |

## Launch checks

| Symptom | Action |
|---|---|
| No active context | Enter the approved folder with the direnv hook, or use `codex-home run NAME`. |
| direnv did not load, or identity/home mismatch | Run `direnv status`; check approval and matching `CODEX_IDENTITY`/`CODEX_HOME` in `.envrc`. Correct and review it before reapproving. |
| Paths moved | Correct `.envrc`'s home, helper `PATH_add`, and API credential-command paths; review and reapprove. Reinstall Finder integration if the helper moved. |
| VS Code CLI missing | Install its `code` shell command or set `CODEX_VSCODE_CLI` to the executable path. macOS also checks standard app locations. |
| Wrong/default editor identity | Close affected windows, reopen through the helper, start a new chat, and verify the account. |
| Codex extension missing | Point `CODEX_VSCODE_EXTENSIONS_DIR` at its existing directory, or install it in that isolated window. |
| Terminal label hidden | Check [terminal title settings](#terminal-context-labels). |

## Keep project files local

For an existing Git repository, setup excludes the generated paths through
`.git/info/exclude`, including the relative directory for nested projects.
It refuses tracked destinations. For a root folder named `project`, the rules
are `/.envrc` and `/.vscode/project.code-workspace`.

If Git is initialized later, add those exact exclusions before staging files.
If a `.gitignore` rule overrides the local exclusions, setup reports the
affected paths. Resolve the rule and confirm that Git lists both files as
ignored. Run this from the project folder.

```bash
git check-ignore -- .envrc ".vscode/$(basename "$PWD").code-workspace"
```

Change and reset preserve rules that predate setup, have no ownership marker,
or are shared by linked worktrees.
To share generated files, first agree on portable paths and identity names,
then remove their local exclusions. Review every `.envrc` change before approval.

## Existing `.envrc`

Setup refuses to overwrite it. Merge this identity block, preserving the
project's other commands:

```bash
export CODEX_IDENTITY="work"
export CODEX_HOME="$HOME/.codex-homes/work"

if [[ ! -d "$CODEX_HOME" ]]; then
  log_error "Missing Codex identity directory: $CODEX_HOME"
  exit 1
fi

watch_file "$CODEX_HOME/config.toml"
if [[ -f "$CODEX_HOME/api-key.env" ]]; then
  watch_file "$CODEX_HOME/api-key.env"
fi
if [[ -f "$CODEX_HOME/.env" ]]; then
  watch_file "$CODEX_HOME/.env"
fi
```

Read the complete file, correct paths copied from another machine, then run
`direnv allow` again. Do not load the identity's key with `dotenv_if_exists`;
Codex's credential command reads it when authenticating. Older `env_key`
identities can use [explicit migration](security.md#secret-exposure-boundaries).
If setup stopped at this existing file, also create the workspace below;
`project` has not generated it.

For a required check in a custom `.envrc`, use `exit 1` on failure. A sourced
`.envrc` can `return 1` or finish with a failed command while direnv still
passes exports collected so far to the editor. The launcher checks the loaded
identity and home after direnv runs.

## Existing VS Code workspace

The launcher opens `.vscode/<folder-name>.code-workspace` (or the legacy
`.vscode/codex-context.code-workspace`). It does not select an arbitrary
workspace filename. Keep any unrelated workspace intact.

If the recognized file is missing, create it with this complete structure;
`".."` opens the project folder from `.vscode`. If it exists, merge only the
labels you need, preserving its folders, tasks, and other settings:

```json
{
  "folders": [{ "path": ".." }],
  "settings": {
    "window.title": "my-project [CODEX: WORK]",
    "workbench.colorCustomizations": {
      "statusBar.background": "#1F883D",
      "statusBar.foreground": "#FFFFFF"
    }
  }
}
```

Labels help identify windows; the launch environment selects the account.
Keep a manually created workspace local with the [same Git exclusions](#keep-project-files-local).
Custom files can launch through the helper; automatic review/change/reset
commands still require untouched generated templates.

## Change or remove a folder's Codex context

Close the affected editor and Codex chats, then switch an untouched generated
context:

```bash
codex-home project-change NEW_IDENTITY "/path/to/project"
```

The helper requires untracked regular files matching its templates, revokes
approval, and replaces both generated files. A failed replacement attempts
restoration; failed restoration retains backups and reports their location.
Read the new `.envrc`, approve it, and reopen through the helper.

After renaming a folder, run `project-change` with the same identity to repair a
single untouched workspace from the old folder name. Review and approve the
context at its new path. Multiple candidates or customized files need manual
recovery.

For removal, use the [dedicated removal procedure](remove-folder-context.md).
Changing terminal directories, VS Code Profiles, or the account-menu sign-in
does not switch an existing chat to another saved home.

### Manual recovery for a custom or shared setup

[Back up the affected files](remove-folder-context.md#1-find-and-back-up-the-affected-files)
and [revoke approval](remove-folder-context.md#2-stop-loading-the-old-environment).
Update only the [identity block](#existing-envrc) and
[workspace labels](#existing-vs-code-workspace). Preserve unrelated setup,
review the complete `.envrc`, approve it, and launch a fresh editor session.

## Migrate a generated workspace

For an untouched `.vscode/codex-context.code-workspace`, run
[project-change](#change-or-remove-a-folders-codex-context) with the identity
already selected. This creates the folder-named workspace, updates exclusions,
and removes legacy key-loading lines. Review and reapprove it. Customized or
shared files need [manual recovery](#manual-recovery-for-a-custom-or-shared-setup).

## Terminal context labels

Interactive `codex-home run` shows **[CODEX: NAME]** and keeps it in the terminal
title while running. It clears the label on exit and restores the previous
title where supported. A launch-only `tui.terminal_title=[]` override prevents
Codex replacing it; saved settings stay intact. Redirected streams and
`TERM=dumb` skip title controls. Plain `codex` uses its own title settings.

For hidden labels, enable application-controlled titles in
[iTerm2](https://iterm2.com/documentation-session-title.html) or
[Terminal](https://support.apple.com/guide/terminal/trml15228/mac).
U-M launches also show the broader scope's low-sensitivity warning; see
[scope boundaries](umgpt.md#guardrail-boundaries).

## Try switching identities

Sign in to identities called `work` and `personal` and verify each account.
Create a disposable Git folder to try switching.
[Account verification](commands.md#check-the-selected-identity)

```bash
demo_dir="$(mktemp -d)"
git -C "$demo_dir" init -q
codex-home project work "$demo_dir"
```

Read `.envrc` and the VS Code workspace at the paths printed by setup. Approve
the context when you understand what it runs.

```bash
cd "$demo_dir"
direnv allow .
direnv exec . codex-home current
direnv exec . codex-home run
```

Check for `WORK` in the identity output and terminal title. Exit Codex, switch
the folder to `personal`, and read the new `.envrc`.

```bash
codex-home project-change personal .
```

Repeat the approval and launch commands and check for `PERSONAL`. To continue
in VS Code, run `codex-home vscode-project` and verify the account in a new chat.

## Other launch environments

- **macOS:** [Finder integration](macos-open-with.md) and
  [optional named Dock copies](macos-open-with.md#optional-named-dock-copies).
- **Remote SSH, WSL, containers:** install the helper and create identities on
  the side running Codex. Host paths may not exist there. Keep credentials out
  of repositories and container images.

Reference: [VS Code isolated instances](https://code.visualstudio.com/docs/configure/command-line#_isolating-vs-code-instances).
