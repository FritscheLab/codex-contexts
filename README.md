# Codex Contexts

Use different Codex accounts for different projects. An **identity** is a local
label, such as `work`, for a login or API provider and its saved settings and
sessions. A folder can select an identity when you launch Codex.

Start with [manual setup](docs/manual-setup.md) to create your own files and
launch Codex directly. The helpers below automate those same steps.

## Start here

> **Choose the launch route for every session.** If you use the helpers for
> a project with electronic protected health information (ePHI), assign the
> folder to the intended Toolkit identity. Start in the direnv-approved
> folder with `codex-home run` or `codex-home vscode-project`, or use Finder's
> **Open in Codex Project** action. Plain `codex` and ordinary **Open With > VS Code**
> bypass the helper's checks and can use a different identity. The helper does
> not enforce ePHI approval. Keep ePHI out until you confirm the active Toolkit
> route, exact model, and approval for your workflow. [Verify the session](docs/commands.md#check-the-selected-identity) | [ePHI requirements](docs/umgpt.md#check-data-permissions-first)

**Choose an account, assign a folder, then launch.**

Install the prerequisites and clone this repo. **Review the checkout before
running its scripts, including `codex-home help`.** They run with your user
permissions. [Installation and source review](INSTALLATION.md#3-clone-and-validate)

Create one identity using your sign-in method. For API keys, `KEY_ENV` means a
variable name such as `LAB_API_KEY`. Check the provider URL with `codex-home
show NAME` before entering the secret in the hidden `set-key` prompt.
[Credential storage](docs/security.md#where-data-lives)

| Sign-in method | Create your identity | Guide |
|---|---|---|
| A ChatGPT account | `codex-home create-subscription work`, then `codex-home login work` | [ChatGPT](docs/subscriptions.md) |
| A U-M Toolkit key | `codex-home create-umgpt`, then `codex-home set-key umgpt` | [U-M GPT](docs/umgpt.md) |
| Another API key | `codex-home create-api NAME URL MODEL KEY_ENV`, then `codex-home set-key NAME` | [API setup](docs/api-providers.md) |

For ChatGPT logins, check the account and workspace in the browser during sign-in.
[Verify your identity](docs/commands.md#check-the-selected-identity)

For a one-off terminal session, enter your project folder and run
`codex-home run work`, using your identity name. To have the folder select the
identity for future launches, set up its context below.

### Let the folder choose the identity

Replace `work` and the path with your identity name and project directory.

```bash
project_dir="/path/to/project"
codex-home project work "$project_dir"
```

Read the generated `.envrc` and VS Code workspace as text. **`direnv allow`
lets direnv run `.envrc` as your user when the folder loads.** Check any files
it loads and leave it unapproved if anything is unclear. [What approval allows](docs/security.md#what-an-approval-allows)

```bash
direnv allow "$project_dir"
cd "$project_dir"
```

Use the folder's identity in the terminal. `current` should show the label and
home you assigned, for example `WORK subscription` at `~/.codex-homes/work`.

```bash
direnv exec . codex-home current
direnv exec . codex-home run
```

With the shell hook enabled, you can run `codex-home current` and
`codex-home run` directly in the folder. [Shell hook setup](INSTALLATION.md#2-enable-direnv-in-your-shell)

| Where? | Launch |
|---|---|
| VS Code | `codex-home vscode-project` from the approved folder |
| Finder on macOS | [Install the optional right-click action](docs/macos-open-with.md#install-the-finder-integration) |

## Account choice and command permissions

![A project selects the work identity home for a labeled Codex session. Generated commands enter an optional native sandbox; the application and model-provider connection remain outside it.](docs/images/codex-contexts.svg)

Want Codex to edit inside a command sandbox?

```bash
codex-home set-sandbox work workspace-write
```

Use `read-only` for review. The command sandbox limits what Codex commands
can do. Files the agent can read may still be sent to the selected provider.
Check the effective permissions and inspect each command before granting extra
access. [Review a Codex approval request](docs/security.md#before-you-approve-a-codex-command)

<details>
<summary>Reference and troubleshooting</summary>

- [All commands](docs/commands.md) | [Fix a problem](docs/troubleshooting.md)
- [Project setup](docs/projects-vscode.md) | [Two-identity example](docs/projects-vscode.md#try-switching-identities) | [Remove a project context](docs/remove-folder-context.md)
- [Model settings and comparisons](MODELS.md) | [Share skills](docs/skills.md)
- [Security and credentials](docs/security.md) | [Two-page cheatsheet](docs/codex-contexts-cheatsheet.pdf)
- [Contribute](CONTRIBUTING.md) | [Report a vulnerability](SECURITY.md)

</details>

Developed at the [Fritsche Lab](https://fritschelab.org/), University of Michigan.
Inspired by Ryan Welch's labeled `direnv` setup. [MIT License](LICENSE).
