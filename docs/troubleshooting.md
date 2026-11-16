# Troubleshooting

Find the symptom and follow its fix. Run project checks in the affected folder;
commands beginning `./bin/` assume the repository directory.

## Helper commands and updates

| Symptom | First check / owning guide |
|---|---|
| `codex-home: command not found` | Add the clone's `bin` to PATH: [shell setup](../INSTALLATION.md#3-clone-and-validate). |
| Codex CLI is not found on PATH, or login reports `No such file or directory: .../codex` | [Install and verify the terminal CLI](../INSTALLATION.md#1-install-prerequisites). Older launchers report the last PATH location tried, which can be an unrelated directory such as `.lmstudio/bin`. |
| Unknown helper command or old `model_catalog_json` rejection | Run `type -a codex-home`; [update the selected copy](../INSTALLATION.md#updating-this-repository), including Finder if installed. |
| Python cannot import `tomllib` or a test prerequisite is missing | [Install the required versions](../INSTALLATION.md#1-install-prerequisites). |
| SSH agent, proxy, certificate, or external key disappeared | [Opt in to exact environment names](security.md#environment-forwarding). |
| API URL or private key file is rejected | [Provider URL checks](security.md#provider-checks) / [literal key-file requirements](security.md#secret-exposure-boundaries). |

## Opening a project

| Symptom | First check / owning guide |
|---|---|
| `run` has no active project context | Use an explicit NAME, or check the approved `.envrc`: [launch checks](projects-vscode.md#launch-checks). |
| `direnv did not load a Codex identity` | Check `direnv status` and the [identity exports](projects-vscode.md#existing-envrc). |
| `project selects identity ... but CODEX_HOME is ...` | Correct the matching name/home in [custom setup](projects-vscode.md#existing-envrc). |
| Generated paths no longer exist | Update local paths and review/reapprove: [launch checks](projects-vscode.md#launch-checks). Reinstall Finder after moving the clone. |
| VS Code CLI is not found | Install the `code` command or set `CODEX_VSCODE_CLI`: [launch checks](projects-vscode.md#launch-checks). |
| `zsh: permission denied: /path/to/project` | Keep the quoted path on the same command line: [launch examples](projects-vscode.md#launch-an-isolated-window). |
| `failed to launch project` | Read the preceding diagnostic; [launch checks](projects-vscode.md#launch-checks). |
| `cannot read .../.envrc` or `Operation not permitted` | Check the named file's access; macOS [privacy and launch errors](macos-open-with.md#finder-and-launch-errors). |

## Identity labels and VS Code windows

| Symptom | Fix |
|---|---|
| CLI context label is missing | [Launch and terminal title settings](projects-vscode.md#terminal-context-labels). |
| `current` says `default`, or a window has the wrong identity | [Close and relaunch through the helper](projects-vscode.md#launch-checks); ordinary VS Code can use `~/.codex`. |
| Dock icons look identical or keep an old name | [Optional named copies and refresh rules](macos-open-with.md#optional-named-dock-copies). |
| Codex extension is missing | [Extension location / installation](projects-vscode.md#launch-checks). |

## Accounts and models

| Symptom | Fix |
|---|---|
| Identity already exists | Inspect it with `codex-home show NAME`, or choose a new name; creation does not overwrite homes. [Commands](commands.md#create-an-identity-and-sign-in). |
| Wrong ChatGPT account | [Reauthenticate only that identity](subscriptions.md#correct-a-login-made-with-the-wrong-account). |
| HTTP 401/403, `/models` 404, `/responses` failure, or missing deployment | [Provider errors](api-providers.md#provider-errors). |
| Picker shows only bundled OpenAI models or ignores saved choices | [Model-picker recovery](model-reference.md#refresh-and-recovery). |
| A label disagrees with the running account/model | [Verify the selected identity](commands.md#check-the-selected-identity). |

## Finder menus and context removal

| Symptom | Fix |
|---|---|
| Finder action is missing | [Quick Actions / Services checks](macos-open-with.md#finder-and-launch-errors). |
| Menu cannot remove the folder's context | [Run the removal command](remove-folder-context.md#try-removal-from-terminal). |
| Change/reset refuses modified, tracked, incomplete, or symlinked files | [Custom context changes](projects-vscode.md#manual-recovery-for-a-custom-or-shared-setup) / [selective manual removal](remove-folder-context.md#remove-the-settings-manually). |
| Extra VS Code/Open With entries, stale registrations, or obsolete copies | [Preview cleanup and choose its scope](macos-open-with.md#clean-up-generated-apps). |
| Installer failed or an old app needs restoring | [Installation recovery](macos-open-with.md#installation-recovery). |

## Shared skills and validation

| Symptom | Fix |
|---|---|
| A skill was skipped | [Resolve the existing-name conflict](skills.md#conflict-behavior). |
| Need to validate native Codex configuration | `codex-home doctor NAME` may contact services. [Diagnostic commands](commands.md#diagnostics-and-maintenance). |
| Need offline or maintainer checks | [Development checks](../CONTRIBUTING.md#development-setup). |
