# Projects, direnv, and VS Code

A project context selects an identity through `.envrc`; that identity's
`CODEX_HOME` holds its account, provider settings, and sessions. Start with
[Installation](../INSTALLATION.md) and an existing identity. Run
`./bin/codex-home` examples from the clone; bare `codex-home` assumes it is on
`PATH`.

| Task | Go to |
|---|---|
| Connect a new folder | [Generate project files](#generate-project-files) |
| Keep existing environment or editor settings | [Existing `.envrc`](#existing-envrc) / [workspace](#existing-vs-code-workspace) |
| Switch identities | [Change the context](#change-or-remove-a-folders-codex-context) |
| Disconnect a folder | [Remove its context](remove-folder-context.md) |

## Generate project files

Replace `work` and the quoted project path:

```bash
./bin/codex-home project work "/path/to/project"
```

| Generated file | Purpose |
|---|---|
| `.envrc` | Selects the identity, checks its home, adds the helper to PATH, and watches configuration/key changes. It does not export credentials. |
| `.vscode/<folder-name>.code-workspace` | Opens the folder with a `[CODEX: IDENTITY]` title and status-bar color. |

Read both files; `.envrc` is executable shell code. For a read-only review in
VS Code, run `./bin/codex-home project-review "/path/to/project"`.
Then approve the intended file:

```bash
direnv allow "/path/to/project"
```

Keep these machine-specific files local; see [Git exclusions](#keep-project-files-local).

## Run from the terminal

With the [direnv shell hook](../INSTALLATION.md#2-enable-direnv-in-your-shell)
enabled and `.envrc` approved:

```bash
cd "/path/to/project"
codex-home run
```

To select an identity without direnv, use `codex-home run work`. This overrides
the active project selection for that launch. Implicit launches refuse a
different identity/home recorded in a recognized generated project. Use the
helper for its checks; direct Codex launches bypass them.

Options pass through. Use `--` before a prompt or subcommand when omitting the
identity name:

```bash
codex-home run --model MODEL
codex-home run -- resume --last
codex-home run -- "Explain this project"
```

[Verify the selected account and model](commands.md#check-the-selected-identity).

## Launch an isolated window

```bash
./bin/codex-home vscode-project "/path/to/project"
```

Use `./bin/codex-home vscode work "/path/to/project"` to also require that the
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
  return 1
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
./bin/codex-home project-change NEW_IDENTITY "/path/to/project"
```

The helper requires untracked regular files matching its templates, revokes
approval, and replaces both generated files. A failed replacement attempts
restoration; failed restoration retains backups and reports their location.
Read the new `.envrc`, approve it, and reopen through the helper.

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

## Other launch environments

- **macOS:** [Finder integration](macos-open-with.md) and
  [optional named Dock copies](macos-open-with.md#optional-named-dock-copies).
- **Remote SSH, WSL, containers:** install the helper and create identities on
  the side running Codex. Host paths may not exist there. Keep credentials out
  of repositories and container images.

Reference: [VS Code isolated instances](https://code.visualstudio.com/docs/configure/command-line#_isolating-vs-code-instances).
