# Installation

Set up this computer in five steps: install prerequisites, enable project
selection, clone the helper, create an identity, and assign it to a project.
If the helper is already installed, skip to [identity setup](#4-configure-an-identity)
or [project setup](#5-configure-a-project).

Run the helper as your normal user. It needs no administrator rights when
using directories you own; some prerequisites may require them. See
[permissions and managed computers](#do-i-need-administrator-rights) if needed.

## 1. Install prerequisites

The helper runs on macOS and Linux with Bash 3.2 or newer.

| Use | Requirements |
|---|---|
| Run Codex from the terminal | Git, Codex CLI, and `jq` |
| Discover API models, refresh model pickers, or generate a model snapshot | Also install `curl` 7.76.0 or newer |
| Select an identity by project | Also install `direnv` 2.32.2 or newer |
| Open labeled VS Code windows | Also install VS Code and the Codex extension |
| Run the tests | Also install `direnv` 2.32.2 or newer and `expect` |
| Open projects from Finder | macOS only |

### macOS

With [Homebrew](https://brew.sh/):

```bash
brew install git direnv jq
```

macOS includes `curl`; check `curl --version` and use `brew install curl` if it
is older than 7.76.0 and you need model discovery. Follow Homebrew's PATH
instructions so `curl --version` reports the newer version. macOS normally
includes `expect`; if `expect -v` fails, run `brew install expect`.
Install or update the Codex CLI by following the
[official Codex CLI guide](https://learn.chatgpt.com/docs/codex/cli). If you
plan to use VS Code, install VS Code and follow the
[official Codex IDE guide](https://learn.chatgpt.com/docs/codex/ide).

### Debian or Ubuntu

```bash
sudo apt update
sudo apt install bash curl direnv expect git jq
```

Check `curl --version` (7.76.0 or newer for model discovery) and
`direnv version`. If `direnv` is older than 2.32.2, upgrade using the
[official installation guide](https://direnv.net/docs/installation.html).
Earlier releases incorrectly expand shell characters such as `$` in project
paths; the launcher requires the upstream path-escaping fix.
See the [direnv 2.32.2 release notes](https://github.com/direnv/direnv/releases/tag/v2.32.2).

Then install or update the Codex CLI using the
[official Codex CLI guide](https://learn.chatgpt.com/docs/codex/cli). Install
VS Code and the Codex extension only if you want the IDE workflow.

On another Linux distribution, install the same prerequisites with its package
manager. For additional `direnv` options, see the
[official installation guide](https://direnv.net/docs/installation.html).

## 2. Enable direnv in your shell

The shell hook selects an identity when you enter a configured project in a
terminal. Finder and the `codex-home vscode` commands call `direnv` directly
and do not need the hook. You can also skip it when using `codex-home run NAME`.

For zsh, add this line to `~/.zshrc`:

```bash
eval "$(direnv hook zsh)"
```

For Bash, add this line to `~/.bashrc`:

```bash
eval "$(direnv hook bash)"
```

Close and reopen the terminal before continuing. Then verify that the required
commands are available:

```bash
git --version
direnv version
curl --version
jq --version
expect -v
codex --version
```

Install any missing command before running the tests.

## 3. Clone and validate

### Recommended location

On macOS or Linux, clone the repository into a stable, local development
directory such as:

```text
~/Developer/codex-contexts
```

Keep the clone separate from `~/.codex` and `~/.codex-homes`, which hold private
Codex data. Keep those identity directories outside Dropbox, iCloud Drive,
OneDrive, shared drives, and Git repositories.

A different local directory also works. Choose it before configuring projects:
generated `.envrc` files contain absolute paths to the clone and identity home.
If you move either directory, update those paths and run `direnv allow` again.
For projects already in Git, setup excludes the generated `.envrc` and VS Code
workspace through `.git/info/exclude`, without changing the shared `.gitignore`.

### Clone and check the helper

```bash
mkdir -p "$HOME/Developer"
cd "$HOME/Developer"
git clone https://github.com/FritscheLab/codex-contexts.git
cd codex-contexts
./tests/test.sh
./bin/codex-home help
```

The test prints a short start message and `All tests passed.` on success. It
creates disposable identities in a temporary directory and uses mock commands;
it does not need your credentials or contact a provider. If the final pass line
does not appear, see [Troubleshooting](docs/troubleshooting.md).

### Make the command available outside the clone

Run examples beginning with `./bin/codex-home` from the clone directory.
Examples using bare `codex-home` require its `bin` directory on `PATH`, either
from the shell setting below or from an approved generated project `.envrc`.
To run `codex-home` from any directory in future terminals,
add this line to `~/.zshrc` for zsh or `~/.bashrc` for Bash:

```bash
export PATH="$HOME/Developer/codex-contexts/bin:$PATH"
```

Use your clone's location if it differs from `~/Developer/codex-contexts`.
Open a new terminal and run `command -v codex-home` to check it. An `export`
entered at the prompt lasts only for the current shell; `cd` and
`./tests/test.sh` do not belong in your shell startup file.

## 4. Configure an identity

An **identity** is a named Codex configuration stored in its own **home**
(`CODEX_HOME`). Choose the guide for the account or provider you will use:

| Sign-in method | Setup guide |
|---|---|
| ChatGPT account or workspace | [Subscription identities](docs/subscriptions.md) |
| U-M GPT Toolkit API key | [U-M GPT](docs/umgpt.md) |
| Another Responses-compatible API or direct Azure endpoint | [API providers](docs/api-providers.md) |

Follow that guide through verification, then continue to project setup below.
For an existing U-M identity, [Model settings and comparison](MODELS.md) covers
changing defaults and model-picker order.

## 5. Configure a project

A **project context** selects the identity used for a folder. Follow
[Projects, direnv, and VS Code](docs/projects-vscode.md#generate-project-files)
to generate the project files, review them, approve `.envrc`, and launch Codex.
Choose the terminal or VS Code instructions there, then verify the active
identity in the surface you use.

On macOS, you can also install the optional [Finder integration](docs/macos-open-with.md#install-the-finder-integration)
to open configured projects by right-clicking a folder. The project guide
explains [Dock identity labels and how to reopen a window](docs/projects-vscode.md#macos-dock-names).

## Updating this repository

Check for local edits before updating and save any you want to keep. Adjust
the path below if you chose a different clone location:

```bash
cd "$HOME/Developer/codex-contexts"
git status --short
git pull --ff-only
./tests/test.sh
```

An update does not rewrite existing identity homes or project `.envrc` files.
Check the updated guides for setup changes before launching projects.

If you installed the macOS Finder integration, [reinstall it](docs/macos-open-with.md#install-the-finder-integration)
after updating so its app and Quick Action use the current helper. Keep any
custom `CODEX_MACOS_APP_DIR` and `CODEX_MACOS_SERVICES_DIR` values when
reinstalling or uninstalling.

For removal, choose the scope you need:

- [Remove Codex settings from one folder](docs/remove-folder-context.md).
- [Remove extra VS Code entries from Open With](docs/macos-open-with.md#remove-extra-vs-code-entries-from-open-with-on-macos).
- [Uninstall the Finder app, Quick Action, and generated launchers](docs/macos-open-with.md#uninstall-the-finder-integration).

## Machine-local setup

On each computer, install the helper, sign in or add your API key, and configure
your projects again. A clone contains only the source code. It does not bring
across identities, credentials, sessions, logs, `direnv` approvals, VS Code
data, skill links, or the Finder app.

Use your own credentials. If a project includes an `.envrc` from another
computer, read it and update its paths before approving it.

## Do I need administrator rights?

**Not to use Codex Contexts.** Clone it into a directory you own and run it as
your normal user. Administrator rights may be needed to install prerequisites.

| Step | Administrator rights? |
|---|---|
| Clone, run tests, create identities, sign in, or store API keys | No, when using directories you own |
| Edit shell hooks, approve `.envrc`, or configure a project | No; you need write access to your shell config and project |
| Install or remove the Finder app and Quick Action in your home directory | No |
| Install Homebrew on macOS | Usually yes for the initial installation; subsequent `brew install` commands run without `sudo` |
| Install Debian/Ubuntu packages with `apt` | Yes, through `sudo` or your administrator |
| Install Codex CLI or VS Code | Depends on the installation location; a system-wide install may need an administrator |

On a managed computer, ask IT to install any missing prerequisites or provide
an approved user installation. Once they are available, the helper uses your
own home and project directories. Run `codex-home` and the Finder installer
without `sudo` so files and credentials belong to your account. See
[Homebrew's installation notes](https://docs.brew.sh/Installation) for its
permissions requirements.
