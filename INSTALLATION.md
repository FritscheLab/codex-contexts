# Installation

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

## Recommended location

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

## Machine-local setup

On each computer, install the helper, sign in or add your API key, and configure
your projects again. A clone contains only the source code. It does not bring
across identities, credentials, sessions, logs, `direnv` approvals, VS Code
data, skill links, or the Finder app.

Use your own credentials. If a project includes an `.envrc` from another
computer, read it and update its paths before approving it.

## 1. Install prerequisites

The helper runs on macOS and Linux with Bash 3.2 or newer.

| Use | Requirements |
|---|---|
| Run Codex from the terminal | Git, Codex CLI, `curl`, and `jq` |
| Select an identity by project | Also install `direnv` |
| Open labeled VS Code windows | Also install VS Code and the Codex extension |
| Run the tests | Also install `direnv` and `expect` |
| Open projects from Finder | macOS only |

### macOS

With [Homebrew](https://brew.sh/):

```bash
brew install git direnv jq
```

macOS includes `curl` and normally includes `expect`. If `expect -v` fails, run
`brew install expect`. Install or update the Codex CLI by following the
[official Codex CLI guide](https://learn.chatgpt.com/docs/codex/cli). If you
plan to use VS Code, install VS Code and follow the
[official Codex IDE guide](https://learn.chatgpt.com/docs/codex/ide).

### Debian or Ubuntu

```bash
sudo apt update
sudo apt install bash curl direnv expect git jq
```

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

The examples in this repository use `./bin/codex-home`, so adding the helper to
`PATH` is optional. To run `codex-home` from any directory in future terminals,
add this line to `~/.zshrc` for zsh or `~/.bashrc` for Bash:

```bash
export PATH="$HOME/Developer/codex-contexts/bin:$PATH"
```

Use your clone's location if it differs from `~/Developer/codex-contexts`.
Open a new terminal and run `command -v codex-home` to check it. An `export`
entered at the prompt lasts only for the current shell; `cd` and
`./tests/test.sh` do not belong in your shell startup file.

## 4. Configure an identity

Choose the guide for the identity you need:

- [ChatGPT subscription identities](docs/subscriptions.md)
- [Responses-compatible API providers and Azure](docs/api-providers.md)
- [Optional U-M GPT setup](docs/umgpt.md)

From the clone directory, run `./bin/codex-home run NAME`, replacing `NAME`
with the identity you created. To select an identity automatically for a
project or open a labeled VS Code window,
[assign the identity to a project](docs/projects-vscode.md). On macOS, you can
also install the optional [Finder Quick Action](docs/macos-open-with.md):

```bash
./bin/install-macos-open-with
```

It installs `~/Applications/Codex Project.app` and
`~/Library/Services/Open in Codex Project.workflow`. Right-click a project
folder, then choose **Quick Actions > Open in Codex Project** (or **Services**
on some macOS menus). The app opens the current context or offers setup,
change, and removal. **Open With > Codex Project** is an additional route when
Finder offers it for folders.

On macOS, helper-launched VS Code instances have Dock hover names such as
`VS Code - work` and `VS Code - default`. They keep the standard VS Code icon.
See [macOS Dock names](docs/projects-vscode.md#macos-dock-names) for reopening,
the restriction on directly launching or pinning editor copies, and the
original-editor opt-out. After quitting, reopen a configured project through
the Finder **Quick Actions > Open in Codex Project** action or `codex-home`.

After project setup, enter the folder and run `codex-home run`. It uses the
context selected by `direnv`; you do not need to type the identity name each
time. Use `codex-home run NAME` to choose an identity explicitly.

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

If you installed the optional macOS Finder integration, reinstall it after
updating so the application contains the current helper and the Quick Action
points to that app:

```bash
./bin/install-macos-open-with
```

To remove the Finder integration later, run:

```bash
./bin/uninstall-macos-open-with
```

This moves the app and its owned Quick Action to Trash without changing folder
contexts or Codex identity homes. Previous installation backups remain
available. If you customized `CODEX_MACOS_APP_DIR` or `CODEX_MACOS_SERVICES_DIR`,
use the same values for reinstalling and uninstalling. See the
[Finder integration guide](docs/macos-open-with.md) for changing or removing a
folder context and for complete cleanup details.
