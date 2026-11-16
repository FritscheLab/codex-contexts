# Command reference

`codex-home help` lists everyday commands. This page covers the full interface.
Use `./bin/codex-home` from the clone if the command is not on PATH.
`NAME` is a local label; optional `DIR` defaults to the current directory.

## Everyday use

| Command | Purpose |
|---|---|
| `run [NAME] [CODEX_ARGS...]` | Start Codex; omit NAME to use the active project's `CODEX_IDENTITY` |
| `run -- [CODEX_ARGS...]` | Pass a prompt or subcommand without an identity argument |
| `vscode-project [DIR]` | Open VS Code with the project's approved identity |
| `vscode NAME [DIR]` | Open VS Code and check that the project selects NAME |
| `current` | Show selection; refuse a mismatch with a recognized generated project |
| `list [--names]` | List identities; `--names` prints names only |
| `show NAME` | Inspect saved settings without printing secrets |
| `set-sandbox NAME read-only\|workspace-write\|inherit` | Set or remove native sandbox defaults |

[Project workflows](projects-vscode.md) own setup, launch, and switching.

### Keep the context visible in the terminal

`run` adds **[CODEX: NAME]** to the terminal title. See
[terminal context labels](projects-vscode.md#terminal-context-labels) for settings.

### Optional sandbox defaults

Use the [permissions decision table](security.md#optional-native-sandbox) to
choose a mode and check its boundaries. Stored defaults can be overridden.

## Project context

| Command | Purpose |
|---|---|
| `project NAME [DIR]` | Generate `.envrc` and a labeled VS Code workspace |
| `project-review [DIR]` | Open a read-only `.envrc` snapshot for review |
| `project-change NAME [DIR]` | Replace an untouched generated context; revoke approval |
| `project-reset [DIR]` | Remove an untouched generated context and its local Git exclusions |
| `project-fingerprint [DIR]` | Identify the exact generated context for Finder's review flow |
| `project-approve DIR SHA256` | Approve that fingerprint; refuse or revoke approval if the context changes |

[Change a context](projects-vscode.md#change-or-remove-a-folders-codex-context)
or [remove one safely](remove-folder-context.md).

## Create an identity and sign in

| Command | Purpose |
|---|---|
| `create-subscription NAME [file\|keyring]` | Create a separate ChatGPT login home; portable file storage by default |
| `login NAME` | Sign in to that ChatGPT identity |
| `create-api NAME BASE_URL MODEL API_KEY_ENV` | Create a Responses-compatible bearer-key identity |
| `create-azure NAME BASE_URL MODEL API_KEY_ENV API_VERSION` | Create a direct Azure identity |
| `create-umgpt [MODEL [NAME]]` | Create a scoped U-M GPT/o-series identity; saved model/default name if omitted |
| `create-umgpt-low [MODEL [NAME]]` | Create a broader U-M text-model identity labeled LOW-SENSITIVITY DATA ONLY |
| `set-key NAME` | Save the selected API key through a hidden prompt |
| `migrate-api-auth NAME` | Replace a recognized legacy `env_key` setting with command-backed authentication |
| `probe-models BASE_URL` | Prompt for a key and print advertised model IDs without storing it |

Setup: [ChatGPT](subscriptions.md), [API/Azure](api-providers.md), or
[U-M GPT](umgpt.md). `default` uses existing `~/.codex`; creation never overwrites it.

## U-M models: choose → edit → apply → reload

| Command | Purpose |
|---|---|
| `model-settings` | Locate personal settings; compare saved and active choices |
| `models NAME` | Print the live scoped model IDs; does not update a picker |
| `apply-model-settings` | Apply saved defaults/order to the standard U-M identities and existing pickers offline |
| `refresh-models NAME` | Fetch and rebuild that identity's scoped picker |
| `set-umgpt-default umgpt\|umgpt-low MODEL` | Save/apply one default while retaining favorite order |
| `reset-umgpt-defaults` | Overwrite personal defaults/order with the repository template |

Follow [model settings](../MODELS.md#change-defaults-and-order) for the workflow,
or [picker recovery](model-reference.md#refresh-and-recovery) when changes do not appear.

## Diagnostics and maintenance

| Command | Purpose |
|---|---|
| `doctor NAME` | Run Codex diagnostics; may contact services |
| `share-skills NAME [SOURCE_DIR]` | Link personal skills into one additional identity |
| `share-skills-all [SOURCE_DIR]` | Link skills into all additional identities; [conflict rules](skills.md#conflict-behavior) |
| `vscode-open-with NAME` | Register an identity-specific macOS Finder handler |
| `set-umgpt-scope NAME openai-only\|low-sensitivity` | Classify an older U-M identity |
| `snapshot-umgpt-models [NAME [OUTPUT]]` | Save a dated review catalog; defaults to `umgpt` and `docs/umgpt-models-snapshot.md` |
| `help`, `-h`, `--help` | Show everyday commands |

Snapshot regeneration belongs in [Contributing](../CONTRIBUTING.md#update-the-u-m-gpt-model-snapshot).
The snapshot is never read at runtime.

## Compatibility aliases

| Old name | Current name |
|---|---|
| `umgpt-defaults` | `model-settings` |
| `apply-umgpt-defaults` | `apply-model-settings` |

## Check the selected identity

A label identifies local configuration, not the authenticated account.
Check the account/workspace in the browser during sign-in. Then use:

| Surface | Check |
|---|---|
| Saved identity | `codex-home show NAME`: home, provider, model, stored defaults |
| CLI authentication | `codex-home run NAME login status`: authentication method |
| CLI session | `/status`: active model/session; `/permissions`: command permissions |
| VS Code | Start a new chat; check account/API status in the extension's profile menu and its model/permissions controls |
| Project terminal | `codex-home current`: detect a generated project's name/home mismatch; this checks the terminal, not the extension host |

Saved settings are not proof of effective runtime overrides. A missing
`auth.json` alone does not prove sign-out on a managed computer. See OpenAI's
[authentication guide](https://learn.chatgpt.com/docs/auth).

## Environment

| Variable | Default or purpose |
|---|---|
| `CODEX_HOMES_ROOT` | Additional homes; default `~/.codex-homes` |
| `CODEX_UMGPT_MODELS_FILE` | Personal defaults/order; default `$CODEX_HOMES_ROOT/umgpt-models.toml` |
| `CODEX_VSCODE_EXTENSIONS_DIR` | Reuse `~/.vscode/extensions` when present |
| `CODEX_VSCODE_CLI` | Editor CLI command or absolute path; auto-detected |
| `CODEX_VSCODE_DOCK_LABEL` | Default `0`; `1` enables [named macOS copies](macos-open-with.md#optional-named-dock-copies) |
| `CODEX_SKILLS_SOURCE` | Default `~/.codex/skills` |
| `CODEX_CONTEXTS_ENV_ALLOW` | Exact extra names to forward; [policy and examples](security.md#environment-forwarding) |
