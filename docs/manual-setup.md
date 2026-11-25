# Manual setup

## Account folder and project folder

Every launch uses two paths.

- **Account folder** `~/.codex-work` stores the work sign-in, settings, and
  history. `CODEX_HOME` is the environment variable Codex reads for this path.
- **Project folder** `~/Projects/lab-notes` is where your files live.

In this command, `CODEX_HOME` selects the work account and `-C` opens the lab
notes folder. The project path is also the last argument in the
[VS Code example](#optional-vs-code-window).

```bash
CODEX_HOME="$HOME/.codex-work" codex -C "$HOME/Projects/lab-notes"
```

Several projects can share an account folder. [Direnv](#optional-folder-selection-with-direnv)
is an optional command-line tool that loads folder settings from a file named
`.envrc`. Here, the file remembers which account folder to use.

![Native Codex uses a private home per account for login, settings, and history. Set CODEX_HOME directly or use direnv with an approved .envrc to launch in the terminal or VS Code. codex-home adds named launches with context checks, generated project files and window labels, Finder integration, and U-M model picker tools.](images/manual-setup.svg)

## Everyday use

Replace `~/Projects/lab-notes` with your project path in the examples. Once
the account is set up, open the project the same way each time you return.

In Terminal, use the [direct launch command](#account-folder-and-project-folder)
or, after setting up direnv, run the following.

```bash
cd "$HOME/Projects/lab-notes" && direnv exec . codex
```

The `.` means the current folder. `&&` starts Codex only if `cd` succeeds.
`direnv exec` loads the folder's settings for that launch.
If you work in VS Code, open Terminal and reuse the
[VS Code launch command](#optional-vs-code-window) each time.

Check the account and model before using project data. The steps below set up
the account and project the first time.

## 1. Install Codex

On macOS, Homebrew installs Codex. `codex --version` checks that your terminal
can find it. On Linux, use the official installer and run the same version
check. [Codex CLI installation](https://learn.chatgpt.com/docs/codex/cli)

```bash
brew install --cask codex
codex --version
```

Install [direnv](#optional-folder-selection-with-direnv) as well if you want
the project folder to remember its account.

## 2. Create a private home and sign in

`mkdir -m 700` creates a directory with owner-only permissions. Choose a new
one for each account, outside Git and cloud sync. This example uses
`~/.codex-work`.

```bash
mkdir -m 700 "$HOME/.codex-work"
```

`codex login` signs in through your browser. Check the account and workspace
there. `codex login status` checks the sign-in for the selected home.

```bash
CODEX_HOME="$HOME/.codex-work" codex login
CODEX_HOME="$HOME/.codex-work" codex login status
```

Using an API key? Apply the provider's configuration in its own home and use
that home in the launch commands below. Keep keys out of project files.
[U-M GPT Toolkit](https://its.umich.edu/computing/ai/codex-gpt-toolkit) | [U-M data permissions](umgpt.md#check-data-permissions-first) | [Custom providers](https://learn.chatgpt.com/docs/config-file/config-advanced#custom-model-providers)

## 3. Open a project

Use the [launch example above](#account-folder-and-project-folder) with a
folder of sample files. In Codex, `/status` shows the active model and
`/permissions` shows what commands can access. For sensitive work, confirm
the provider, model, and workflow approval before using real data.
[Codex commands](https://learn.chatgpt.com/docs/developer-commands#built-in-slash-commands)

For another account, use a different home, such as `~/.codex-personal`.

### Optional folder selection with direnv

On macOS, Homebrew installs direnv. `direnv version` checks that it is
available. On Linux, use your package manager and run the same check.
[direnv installation](https://direnv.net/docs/installation.html)

```bash
brew install direnv
direnv version
```

Create `~/Projects/lab-notes/.envrc` with this line. If `.envrc` already exists,
review it and preserve any existing setup. Keep credentials out of it.

```bash
export CODEX_HOME="$HOME/.codex-work"
```

Read the file, then run `direnv allow` for that exact path. **That approval
lets direnv run the entire file as your user.** The next command prints the
home selected by the file without inheriting `CODEX_HOME` from your shell.
[direnv commands](https://direnv.net/man/direnv.1.html#commands)

```bash
direnv allow "$HOME/Projects/lab-notes/.envrc"
env -u CODEX_HOME direnv exec "$HOME/Projects/lab-notes" printenv CODEX_HOME
```

If the output matches your chosen home, use the terminal command from
[Everyday use](#everyday-use). Review and approve `.envrc` again after editing
it. From the project folder, `direnv deny ./.envrc` revokes approval.

### Optional VS Code window

Install the Codex extension and make `code` available in your terminal.
[Codex extension](https://learn.chatgpt.com/docs/codex/ide) | [VS Code CLI setup](https://code.visualstudio.com/docs/configure/command-line)

Run this from Terminal to open the project in a new window. The `CODEX_HOME`
assignment passes the account's folder to VS Code, and its local Codex
extension inherits that setting.
`--user-data-dir` gives the account its own editor instance and environment.
Quit that instance before changing its environment. Open a new Codex chat
and verify the account and model.
[VS Code instance isolation](https://code.visualstudio.com/docs/configure/command-line#_isolating-vs-code-instances)

```bash
CODEX_HOME="$HOME/.codex-work" code --new-window \
  --user-data-dir "$HOME/.codex-work/vscode-user-data" \
  "$HOME/Projects/lab-notes"
```

With the repo's helper setup, the short command from the project folder is
`codex-home vscode-project`. [Helper launch](projects-vscode.md#launch-a-separate-vs-code-window)
