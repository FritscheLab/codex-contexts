# Command reference

[Everyday use](#everyday-use) · [Projects](#project-context) · [Models](#u-m-models-choose--edit--apply--reload) · [Create an identity](#create-an-identity-and-sign-in) · [Verify](#check-the-selected-identity) · [Environment](#environment)

For setup, start with [Installation](../INSTALLATION.md). For a printable
reference, [download the two-page cheatsheet](codex-contexts-cheatsheet.pdf).

The sections below follow `./bin/codex-home help`. Prefix each command in the
tables with `./bin/codex-home` from the clone directory.
Examples using bare `codex-home` assume its `bin` directory is on `PATH`,
through [shell setup](../INSTALLATION.md#3-clone-and-validate) or an approved
generated project `.envrc`.

Brackets mean optional arguments. `NAME` is a local identity label;
`PROJECT_DIR` defaults to the current directory.

## Everyday use

| Command | Purpose |
|---|---|
| `run [NAME] [CODEX_ARGS...]` | Run Codex with a context banner and title; omit `NAME` for the active project context |
| `run -- [CODEX_ARGS...]` | Pass a prompt or subcommand to Codex using the active project context |
| `vscode-project [PROJECT_DIR]` | Read the identity from the project's approved `direnv` context and launch VS Code |
| `vscode NAME [PROJECT_DIR]` | Open VS Code with the identity's environment and user data |
| `current` | Show the active project identity |
| `list [--names]` | List identities; `--names` prints names only for scripts |
| `show NAME` | Inspect saved identity settings without printing secrets |

For macOS labels and launch options, see
[Dock names](projects-vscode.md#macos-dock-names).

### Keep the context visible in the terminal

Use `codex-home run` inside an approved project, or `codex-home run work` to
choose an identity explicitly. The helper shows **[CODEX: NAME]** at launch
and in the terminal title. Plain `codex` uses its own title settings.

Options work directly. Put `--` before a prompt or subcommand when omitting
the identity name:

```bash
codex-home run --model MODEL
codex-home run -- resume --last
codex-home run -- "Explain this project"
```

The label identifies the local configuration; [verify the selected
identity](#check-the-selected-identity) before use. See
[terminal labels and settings](projects-vscode.md#terminal-context-labels)
for title behavior and [U-M scope checks](umgpt.md#guardrail-boundaries)
for model restrictions.

## Project context

| Command | Purpose |
|---|---|
| `project NAME [PROJECT_DIR]` | Create a project's `.envrc` and labeled VS Code workspace |
| `project-review [PROJECT_DIR]` | Review a read-only `.envrc` snapshot in VS Code |
| `project-change NAME [PROJECT_DIR]` | Safely replace an untouched generated project context |
| `project-reset [PROJECT_DIR]` | Remove an untouched generated project context and its local exclusions |

See [Projects, direnv, and VS Code](projects-vscode.md) for setup, review, and
approval, or [Remove Codex settings from a folder](remove-folder-context.md)
for removal and recovery.

## U-M models: choose → edit → apply → reload

Use [Model settings and comparison](../MODELS.md) to compare prices, context
windows, and benchmarks, then edit and apply your choices. The
[model reference](model-reference.md) covers sources, alternate settings, and
recovery.

| Command | Purpose |
|---|---|
| `model-settings` | Show the personal settings file, saved defaults, preferred order, and active defaults; initialize the file if needed |
| `models NAME` | List live model IDs using the stored identity key, filtered by its U-M scope when applicable; does not update the picker |
| `apply-model-settings` | Apply edited defaults and preferred order to both existing standard U-M identities and their saved pickers, without a network request |
| `refresh-models NAME` | Fetch the live gateway catalog and rebuild that U-M identity's CLI and VS Code model picker |
| `set-umgpt-default umgpt\|umgpt-low MODEL` | Save one default and update that standard identity if it exists, keeping preferred order |
| `reset-umgpt-defaults` | Replace local defaults and preferred order with the repository template and apply to existing standard identities |

After picker changes, restart the CLI or run **Developer: Reload Window** in
VS Code and start a new Codex chat.

## Create an identity and sign in

| Command | Purpose |
|---|---|
| `create-subscription NAME` | Create a home for a ChatGPT login |
| `login NAME` | Sign in to a subscription identity |
| `create-umgpt [MODEL [NAME]]` | Create a U-M GPT identity restricted to GPT and o-series text IDs through U-M's Azure OpenAI-backed path; omit `MODEL` to use its saved default |
| `create-umgpt-low [MODEL [NAME]]` | Create a broader U-M text-model identity labeled **LOW-SENSITIVITY DATA ONLY**; omit `MODEL` to use its saved default |
| `create-api NAME BASE_URL MODEL API_KEY_ENV` | Create an API identity using a bearer key and Responses API |
| `create-azure NAME BASE_URL MODEL API_KEY_ENV API_VERSION` | Create a direct Azure provider |
| `set-key NAME` | Prompt without echo and save an API key locally |
| `probe-models BASE_URL` | Prompt for a key and print model IDs advertised by a provider before creating an identity |

See [Installation](../INSTALLATION.md), [ChatGPT subscriptions](subscriptions.md),
[U-M GPT](umgpt.md), or [API providers](api-providers.md) for setup examples.

## Diagnostics and maintenance

| Command | Purpose |
|---|---|
| `doctor NAME` | Run Codex diagnostics for an identity; may use the network |
| `share-skills NAME [SOURCE_DIR]` | Link personal skills into one additional home |
| `share-skills-all [SOURCE_DIR]` | Link personal skills into all additional homes |
| `vscode-open-with NAME` | Register an identity-specific macOS Open With entry; see [Finder integration](macos-open-with.md) |
| `set-umgpt-scope NAME openai-only\|low-sensitivity` | Assign a scope to an existing U-M GPT identity |
| `snapshot-umgpt-models [NAME [OUTPUT]]` | Save a dated informational catalog; defaults to `umgpt` and `docs/umgpt-models-snapshot.md` |
| `help` | Show the command reference; `-h` and `--help` also work |

Snapshots record the raw catalog and both local scope classifications; the
helper never reads them at runtime. See the [current snapshot](umgpt-models-snapshot.md)
and [filtering rules](umgpt.md#exact-local-filtering-rules).

### Share personal skills

Use `share-skills-all` to link existing personal skills into additional homes.
See [Sharing skills](skills.md) for setup, conflicts, and discovery boundaries.

## Compatibility aliases

| Command | Equivalent command |
|---|---|
| `umgpt-defaults` | `model-settings` |
| `apply-umgpt-defaults` | `apply-model-settings` |

## Identity selection

`NAME` is an arbitrary local label, not verification of an account, plan, or
model. The special name `default` uses the existing `~/.codex`; the helper
does not create that home. `run` without `NAME` uses `CODEX_IDENTITY`, normally
set by the project's `direnv` context.

### Check the selected identity

During sign-in, check the intended account and workspace in the browser.

From the clone directory, inspect an identity's saved configuration and the
CLI authentication method without printing credentials:

```bash
./bin/codex-home show NAME
./bin/codex-home run NAME login status
./bin/codex-home run NAME
```

Replace `NAME` with the identity you created. In the **CLI**, `/status` shows
the active model and session configuration. `login status` checks the CLI
authentication method; it does not establish the intended account or workspace.

In **VS Code**, start a new Codex chat after switching identities. Check the
extension's account or API-key status in its profile menu and the selected model
in its model picker. Open a fresh integrated terminal and run:

```bash
codex-home current
```

Compare the selected home and configured provider/model with the window label.
`current` and `show` read local selection/configuration; they are not proof of
the authenticated account or effective runtime overrides. A missing `auth.json`
alone does not prove sign-out on a managed computer; check CLI `login status`
or the extension's profile menu.

For a missing or stale U-M model picker, follow [model refresh and recovery](model-reference.md#refresh-and-recovery).

See OpenAI's [authentication guide](https://learn.chatgpt.com/docs/auth) and
[CLI and IDE command reference](https://learn.chatgpt.com/docs/developer-commands)
for the corresponding checks in each surface.

## Environment

| Variable | Purpose and default |
|---|---|
| `CODEX_HOMES_ROOT` | Root for additional identities; defaults to `~/.codex-homes` |
| `CODEX_UMGPT_MODELS_FILE` | Personal U-M defaults and preferred model order; defaults to `$CODEX_HOMES_ROOT/umgpt-models.toml` |
| `CODEX_VSCODE_EXTENSIONS_DIR` | Existing VS Code extensions directory to reuse; defaults to `~/.vscode/extensions` when it exists |
| `CODEX_VSCODE_CLI` | VS Code CLI command or absolute path; auto-detected when unset |
| `CODEX_VSCODE_DOCK_LABEL` | Named macOS VS Code copies; defaults to `1`, or set `0` to use the installed editor |
| `CODEX_SKILLS_SOURCE` | Canonical personal skills directory; defaults to `~/.codex/skills` |
