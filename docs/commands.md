# Command reference

For a printable reference, [download the two-page cheatsheet](codex-contexts-cheatsheet.pdf).

Prefix each command below with `./bin/codex-home` from the clone directory.
If its `bin` directory is on `PATH`, use `codex-home` instead.

| Command | Purpose |
|---|---|
| `create-subscription NAME` | Create a home for a ChatGPT login |
| `create-api NAME URL MODEL ENV` | Create an API identity using a bearer key and Responses API |
| `create-azure NAME URL MODEL ENV VERSION` | Create a direct Azure provider |
| `create-umgpt MODEL [NAME]` | Create an optional U-M GPT identity |
| `set-key NAME` | Prompt without echo and save an API key locally |
| `probe-models URL` | Print model IDs advertised by a provider before creating an identity |
| `models NAME` | List models using a stored identity key |
| `login NAME` | Sign in to a subscription identity |
| `project NAME [DIR]` | Create a project's `.envrc` and labeled VS Code workspace |
| `project-change NAME [DIR]` | Safely replace an untouched generated project context |
| `project-reset [DIR]` | Remove an untouched generated project context and its local exclusions |
| `project-review [DIR]` | Review a read-only `.envrc` snapshot in VS Code |
| `vscode NAME [DIR]` | Open VS Code with the identity's environment and user data |
| `vscode-project [DIR]` | Read the identity from `direnv` and launch VS Code |
| `run [NAME] [ARGS...]` | Run Codex with a context banner and title; omit `NAME` for the active project context |
| `run -- [ARGS...]` | Pass a prompt or subcommand to Codex using the active project context |
| `doctor NAME` | Run Codex diagnostics for an identity; may use the network |
| `show NAME`, `current`, `list` | Show identity details without printing secrets; use `list --names` in scripts |
| `share-skills NAME [SOURCE]` | Link personal skills into one additional home |
| `share-skills-all [SOURCE]` | Link personal skills into all additional homes |

Run `./bin/codex-home help` for usage.

## Keep the context visible in the terminal

Inside a configured project, start Codex with:

```bash
codex-home run
```

The helper uses `CODEX_IDENTITY`, which the `direnv` shell hook sets when you
enter the project. If no context is active, it asks you to choose one.
Existing project setups work without changes.

Options work directly. Use `--` before a prompt or subcommand so it is not
read as an identity name:

```bash
codex-home run --model MODEL
codex-home run -- resume --last
codex-home run -- "Explain this project"
```

To choose an identity explicitly, use `codex-home run work`. This also works
without `direnv` and overrides the project's selection for that launch.

In an interactive terminal, the helper displays **[CODEX: NAME]** at launch
and keeps it in the tab/window title while Codex runs. It clears the label on
exit and restores the previous title when the terminal supports a title stack.
This also works with existing identities; no configuration migration is needed.

Use `codex-home run` to get this label. Running `codex` directly uses its
own title settings, even inside a `direnv` project. The helper's context name
is a local label; check `/status` for the signed-in account and provider.

Codex's footer currently has no custom context-name item. The helper uses a
launch-only `tui.terminal_title=[]` override to keep Codex from replacing the
terminal title. It leaves saved settings alone and skips terminal controls
when input or output is redirected, or `TERM=dumb`.

If the label is hidden, check your terminal's title settings. In iTerm2, allow
applications to change the title and include the session name in the title.
See [iTerm2 session titles](https://iterm2.com/documentation-session-title.html),
[Terminal window titles](https://support.apple.com/guide/terminal/trml15228/mac),
and [Codex TUI settings](https://learn.chatgpt.com/docs/config-file/config-sample).

## Check the selected identity

```bash
./bin/codex-home current
./bin/codex-home show umgpt
./bin/codex-home list
```

Compare the result with the VS Code window title and `/status` in a new Codex
session. Start a new chat after switching identities.

## Share personal skills

```bash
./bin/codex-home share-skills-all
```

This links personal skills from `~/.codex/skills` into each additional identity.
It leaves `.system` alone and skips existing skills with the same name. Rerun
it after adding a skill. See [Sharing skills](skills.md) for details.
