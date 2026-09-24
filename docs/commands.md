# Command reference

For a printable reference, [download the two-page cheatsheet](codex-contexts-cheatsheet.pdf).

Prefix each command below with `./bin/codex-home` from the clone directory.
If its `bin` directory is on `PATH`, use `codex-home` instead.

| Command | Purpose |
|---|---|
| `create-subscription NAME` | Create a home for a ChatGPT login |
| `create-api NAME URL MODEL ENV` | Create an API identity using a bearer key and Responses API |
| `create-azure NAME URL MODEL ENV VERSION` | Create a direct Azure provider |
| `create-umgpt [MODEL [NAME]]` | Create a U-M GPT identity restricted to GPT and o-series text IDs through U-M's Azure OpenAI-backed path; omit `MODEL` to use its saved default |
| `create-umgpt-low [MODEL [NAME]]` | Create a broader U-M text-model identity labeled **LOW-SENSITIVITY DATA ONLY**; omit `MODEL` to use its saved default |
| `umgpt-defaults` | Show the U-M GPT defaults and initialize their editable TOML file if needed |
| `set-umgpt-default umgpt\|umgpt-low MODEL` | Save one default and update that standard identity if it exists |
| `apply-umgpt-defaults` | Validate edited defaults and apply them to existing standard U-M GPT identities |
| `reset-umgpt-defaults` | Replace local defaults with the checked-in recommendations and update existing standard identities |
| `set-umgpt-scope NAME openai-only\|low-sensitivity` | Assign a scope to an existing U-M GPT identity |
| `set-key NAME` | Prompt without echo and save an API key locally |
| `probe-models URL` | Print model IDs advertised by a provider before creating an identity |
| `models NAME` | List models using a stored identity key, filtered by its U-M GPT scope when applicable |
| `snapshot-umgpt-models [NAME [OUTPUT]]` | Write a dated snapshot of the raw U-M catalog and both local scope classifications; defaults to `umgpt` and `docs/umgpt-models-snapshot.md` |
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

On macOS, `vscode` and `vscode-project` give standard VS Code instances a Dock
hover name such as `VS Code - work`. Set `CODEX_VSCODE_DOCK_LABEL=0` to use
the original editor instead of a named copy. Both paths use the editor's CLI.
See [macOS Dock names](projects-vscode.md#macos-dock-names).

## Keep the context visible in the terminal

Inside a configured project, start Codex with:

```bash
codex-home run
```

The helper uses `CODEX_IDENTITY`, which the `direnv` shell hook sets when you
enter the project. If no context is active, it asks you to choose one.

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

Use `codex-home run` to get this label. Running `codex` directly uses its
own title settings, even inside a `direnv` project. The helper's context name
is a local label; check `/status` for the signed-in account and provider.

For U-M GPT identities, `codex-home run` also validates the selected model.
The normal `umgpt` identity accepts GPT and o-series text IDs only and pins
them to U-M's Azure OpenAI-backed Toolkit gateway. It is not a direct OpenAI
account or API route. An `umgpt-low` identity permits other general text models
and prints a **LOW-SENSITIVITY DATA ONLY** warning. These local scopes do not
establish institutional approval for a model, workflow, or type of data. See
[U-M GPT](umgpt.md#what-azure-openai-means-here).

The helper labels the terminal title, not Codex's footer. It uses a launch-only
`tui.terminal_title=[]` override to keep Codex from replacing the
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

## Keep U-M GPT defaults current

Three sources serve different purposes:

- `config/umgpt-models.toml` in the clone contains the repository's two
  version-controlled recommendations.
- `$CODEX_HOMES_ROOT/umgpt-models.toml` contains your local defaults for the
  standard `umgpt` and `umgpt-low` identities.
- `codex-home models NAME` queries the gateway's current scoped model catalog.

Show the repository and local values together, then update a local default:

```bash
codex-home umgpt-defaults
codex-home set-umgpt-default umgpt MODEL
codex-home set-umgpt-default umgpt-low MODEL
```

You can instead edit the path printed by `umgpt-defaults`, then run
`codex-home apply-umgpt-defaults`. After pulling updated repository
recommendations, adopt both of them explicitly with:

```bash
codex-home reset-umgpt-defaults
```

Reset overwrites local choices and updates existing standard identities. None
of these default-setting commands changes additional named identities. Use
`codex-home models umgpt` or `codex-home models umgpt-low` to discover the
current gateway models; neither TOML file is a live catalog.

For review and change tracking, a maintainer can refresh the informational
[U-M GPT model snapshot](umgpt-models-snapshot.md):

```bash
codex-home snapshot-umgpt-models umgpt docs/umgpt-models-snapshot.md
```

This captures the raw catalog visible to that credential and classifies each
ID under both local rules. It is dated and credential-specific. The helper
never reads the snapshot at runtime, and inclusion does not establish Codex
compatibility or institutional approval. See the
[exact filtering rules](umgpt.md#exact-local-filtering-rules).

## Share personal skills

```bash
./bin/codex-home share-skills-all
```

This links personal skills from `~/.codex/skills` into each additional identity.
It leaves `.system` alone and skips existing skills with the same name. Rerun
it after adding a skill. See [Sharing skills](skills.md) for details.
