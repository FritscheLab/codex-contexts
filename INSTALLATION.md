# Installation

Codex Contexts selects separate local account homes and opens projects with
that choice. Use the helpers below, or [set it up manually](#manual-setup).

![Account settings live in a named home; project setup adds local context files; optional macOS integration adds a Finder app and Services workflow. The helper uses normal user access, and manual setup is possible.](docs/images/local-footprint.svg)

The helper needs your normal write access to the chosen folders, not `sudo`.
Installing prerequisites may need administrator rights. macOS may ask for
access to protected project folders. Shell-startup changes below are manual.

<details>
<summary>Exactly what gets written</summary>

Default locations; custom roots and Git worktrees can differ.

| Choice | Files or state written |
|---|---|
| Create an identity | `~/.codex-homes/NAME/config.toml`, `.identity-kind`, and small lock/metadata files. New homes are private (`700`); helper-written settings and new key files use `600`. The `default` identity refers to existing `~/.codex`. |
| Sign in / save an API key | Codex writes `auth.json` in that home, or uses the explicitly selected OS keyring. `set-key` writes `api-key.env`. Keep the home outside Git and cloud sync. |
| Assign a project | `PROJECT/.envrc`, `.vscode/<folder>.code-workspace`, and local Git exclusions, usually `.git/info/exclude`. New project files contain paths and labels, not keys. |
| Approve direnv | Its own [approval record](https://direnv.net/man/direnv.1.html#files) under `~/.local/share/direnv/allow` by default. Read `.envrc` before allowing it. |
| Use Codex / VS Code | Codex creates sessions/logs in the selected home; editor state uses its `vscode-user-data/`. Existing shared extensions may be reused. |
| Enable extras | U-M settings/catalogs and shared-skill links live under the homes root. Optional Finder integration writes `~/Applications/Codex Project.app` and `~/Library/Services/Open in Codex Project.workflow`; named editor copies live inside the identity home. |

First project setup refuses existing or tracked destinations. Change/reset
manage recognized generated files; reset keeps accounts and credentials.
Finder uninstall moves owned integration bundles to Trash; cleanup `--apply`
permanently deletes recognized generated copies/backups. See
[removal](docs/remove-folder-context.md) and [macOS cleanup](docs/macos-open-with.md).

</details>

<a id="manual-setup"></a>
<details>
<summary>Manual setup: use native Codex and VS Code instead</summary>

For a ChatGPT login, choose a new private home and use it consistently:

```bash
mkdir -m 700 "$HOME/.codex-work"
CODEX_HOME="$HOME/.codex-work" codex login
CODEX_HOME="$HOME/.codex-work" codex -C "/path/to/project"
CODEX_HOME="$HOME/.codex-work" code --new-window \
  --user-data-dir "$HOME/.codex-work/vscode-user-data" \
  "/path/to/project"
```

Use a different home/editor data directory for each account. Edit that home's
`config.toml` directly for [native provider or permission settings](https://learn.chatgpt.com/docs/config-file/config-basic).
Project labels, direnv, model helpers, and Finder integration are optional.
The manual route omits this repo's launch checks, environment filtering, and
credential parser. Quit the identity's editor before changing its environment.

</details>

**Scope and limits:** this is an account launcher, not a VM, credential vault,
or security policy. Other launchers can bypass selection. Credentials can be
exposed, commands can alter data, and requests go to your chosen provider.
There is no guarantee of correct routing, security, privacy, or compatibility.
[Permission boundaries](docs/security.md) explain the controls and checks.

## 1. Install prerequisites

Use macOS or Linux with Bash 3.2+, Python 3.11+, and the
[Codex CLI](https://learn.chatgpt.com/docs/codex/cli).

| System | Install the supporting tools |
|---|---|
| macOS, with [Homebrew](https://brew.sh/) | `brew install git direnv jq python` |
| Debian / Ubuntu | `sudo apt install bash bubblewrap curl direnv expect git jq python3` |

Terminal commands need a `codex` executable on `PATH`. The VS Code extension's
bundled copy may be available only inside the editor. On macOS with Homebrew,
install the CLI separately:

```bash
brew install --cask codex
```

For Linux or other installation methods, follow the
[Codex CLI installation guide](https://learn.chatgpt.com/docs/codex/cli).
Verify from the same terminal where you will run `codex-home`:

```bash
command -v codex
codex --version
```

Expect an executable path and a `codex-cli` version. If either check fails,
finish CLI installation or add its executable directory to `PATH` before
running `codex-home login`, `run`, or `doctor`.

Check `python3 --version` and `direnv version`: Python must be 3.11+ and
`direnv` 2.32.2+. Model discovery also needs curl 7.76+. On older systems,
[upgrade direnv](https://direnv.net/docs/installation.html) or Python first.
macOS normally includes `expect`; install it with Homebrew if `expect -v` fails.
Python packages are not needed.

Native checks on macOS, **2026-11-16**: CLI **0.156.1** and the extension's
**0.169.0-alpha.11.1** binary passed configuration, local auth, loopback tool
calls, and sandbox write checks. This does not verify GUI sign-in or a remote
provider; run the [workflow compatibility check](docs/api-providers.md#validate-compatibility).

Want VS Code? Install it and the
[Codex extension](https://learn.chatgpt.com/docs/codex/ide).

## 2. Enable direnv in your shell

Optional: the hook selects your identity when you enter a project.
Explicit `codex-home run NAME` and the VS Code/Finder launchers work without it.

| Your shell | Add to its startup file |
|---|---|
| zsh: `~/.zshrc` | `eval "$(direnv hook zsh)"` |
| Bash: `~/.bashrc` | `eval "$(direnv hook bash)"` |

Open a new terminal after editing the file.

## 3. Clone and validate

```bash
mkdir -p "$HOME/Developer"
cd "$HOME/Developer"
git clone https://github.com/FritscheLab/codex-contexts.git
cd codex-contexts
./tests/test.sh
```

Expect `All tests passed.` Tests use temporary identities and mock programs;
they need no credentials or provider connection.

Add this line to your shell startup file, using your clone's actual path:

```bash
export PATH="$HOME/Developer/codex-contexts/bin:$PATH"
```

Open a new terminal and run `codex-home help`. Keep the clone in a stable
location; generated project files point to it.

## 4. Configure an identity

| Your sign-in | Follow |
|---|---|
| ChatGPT account | [ChatGPT setup](docs/subscriptions.md) |
| U-M Toolkit API key | [U-M GPT setup](docs/umgpt.md) |
| Another API key or Azure endpoint | [API setup](docs/api-providers.md) |

## 5. Configure a project

Return to [Start here](README.md#start-here) for the short workflow.
[Project setup](docs/projects-vscode.md) covers existing `.envrc` files,
switching identities, and VS Code. On macOS,
[Finder integration](docs/macos-open-with.md#install-the-finder-integration)
is optional.

## Updating this repository

From the clone, save any local edits before updating:

```bash
git status --short
git pull --ff-only
./tests/test.sh
```

Existing accounts and projects are not rewritten. For an older API home,
`codex-home migrate-api-auth NAME` moves a recognized legacy key out of Codex's
automatically exported `.env`. Older generated contexts may also export keys
into the shell. Refresh an untouched context with
`codex-home project-change NAME PROJECT_DIR`, then review and reapprove it.
See [migration and credentials](docs/security.md#secret-exposure-boundaries).
Reinstall the Finder integration if you use it.

## Machine-local setup

Repeat account sign-in and project setup on each computer. Keep credentials
and identity homes outside Git, cloud-sync folders, and shared drives.
[Removal instructions](docs/remove-folder-context.md) cover removing a folder's context.

## Do I need administrator rights?

Run the helper and Finder installer as your normal user. Administrator rights
may be needed to install prerequisites; managed-computer users can ask IT.
