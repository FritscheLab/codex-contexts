# Troubleshooting

## The CLI does not show the context name

Inside a configured project, launch it with `codex-home run`. To choose an
identity explicitly, use `codex-home run NAME`. The helper prints a context
banner and keeps **[CODEX: NAME]** in the terminal tab/window title. Plain
`codex` does not use this launcher label. The helper labels the terminal
title, not Codex's footer.

If the title stays hidden, allow applications to set titles in your terminal's
settings. See [Terminal context labels](commands.md#keep-the-context-visible-in-the-terminal).

## `run` reports no active project context

`codex-home run` reads `CODEX_IDENTITY` from your shell. Check the
[direnv shell hook](../INSTALLATION.md#2-enable-direnv-in-your-shell), review
and approve the project's `.envrc`, then leave and re-enter the folder. You
can also choose a context directly with `codex-home run NAME`.

Run `command -v codex-home` to identify the helper your shell uses. Follow
[Updating](../INSTALLATION.md#updating-this-repository) to refresh it and the
Finder integration; existing projects do not need to be configured again.

## `zsh: permission denied: /path/to/project`

The project path was interpreted as a new command, usually because it was put
on a separate line. Run one complete command and quote paths containing spaces:

```bash
./bin/codex-home vscode personal "/path/to/project"
```

## VS Code Dock icons look identical on macOS

The icons use the standard VS Code artwork. The helper prepares named editor
copies under `$CODEX_HOME/vscode-editor/`; hover over a running icon to read
`VS Code - NAME`, including `VS Code - default`. Window titles and status-bar
colors also identify the context.

Quit the intended identity and reopen its project through the helper, Finder's
**Open in Codex Project** Quick Action/Service, or a file manager's
**Open With > VS Code - NAME** handler. The identity-specific handler checks
that the folder's `.envrc` selects the same identity before opening it. If
`CODEX_VSCODE_DOCK_LABEL=0` is set, the helper
uses the original installed editor without the named editor copy. An
already-running identity keeps its original application until it quits.

Clicking a running Dock icon focuses that editor. **After quitting, use
Finder > Quick Actions > Open in Codex Project, a file manager's Open With
> VS Code - NAME, or `codex-home vscode`.** Do not pin or directly launch the generated editor
copies under the identity home: a direct macOS launch does not supply the
identity environment and isolated user-data arguments.

If the installed VS Code version changed, the helper waits until the identity
is stopped before refreshing its application copy. The existing copy is used
while the identity is running. For launch or approval errors, run the helper
from a terminal to read the diagnostic. If macOS reports `Operation not
permitted`, inspect the named path and its privacy permissions. See
[macOS Dock names](projects-vscode.md#macos-dock-names).

## Finder does not show Codex Project for a folder

Install or update the Finder integration with `./bin/install-macos-open-with`,
then right-click the folder itself and choose **Quick Actions > Open in Codex
Project** (or **Services**). A native **Open With** menu is not available for
every folder context. Check **Finder > Services** and enable the action in
Keyboard Shortcuts > Services if necessary. See the
[Finder menu checks](macos-open-with.md#if-open-in-codex-project-is-not-listed).

## VS Code CLI is not found

The helper checks `code` on `PATH` and standard macOS application paths. If
needed, open the VS Code Command Palette and run **Shell Command: Install 'code'
command in PATH**, or set:

```bash
export CODEX_VSCODE_CLI="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
```

## `direnv did not load a Codex identity`

The launcher cannot obtain both `CODEX_IDENTITY` and `CODEX_HOME` from the
project's `.envrc`. The file may be unapproved or skipped by `direnv`.

Inspect the file and approval state before changing approval:

```bash
cd "/path/to/project"
direnv status
```

Read `.envrc` in a text editor and confirm its identity, home path, and other
shell commands are intended. Approve it only after that review:

```bash
direnv allow "/path/to/project"
```

## `cannot read .../.envrc`

Inspect the named path, file permissions, and Codex Project's folder access
under macOS Privacy & Security. `direnv allow` cannot fix a file-access denial.
Once the file is readable, review it and check its approval with `direnv status`.

## `project selects identity ... but CODEX_HOME is ...`

The identity name and home directory in `.envrc` disagree. Correct the
configuration through **Set or change Codex identity…**, or follow the
[project recovery instructions](projects-vscode.md#manual-recovery-for-a-custom-or-shared-setup).
If the home directory is missing, restore or configure that identity before
opening the project.

For errors from obsolete Finder or Dock entries, follow
[launcher recovery](macos-open-with.md#replace-obsolete-launcher-entries).

## `current` says `default` in VS Code

An ordinary VS Code window probably inherited another running instance's
environment. Close that identity's window and launch through:

```bash
./bin/codex-home vscode NAME "/path/to/project"
```

The separate `--user-data-dir` gives VS Code the intended identity environment.
Open a new Codex chat and integrated terminal after launch.

## The Codex extension is missing in an isolated window

The launcher reuses `~/.vscode/extensions` when it exists. If extensions live
elsewhere, set `CODEX_VSCODE_EXTENSIONS_DIR`, or install the Codex extension in
that isolated VS Code instance.

## Identity already exists

Creation commands refuse to overwrite existing state. Inspect it:

```bash
./bin/codex-home show NAME
```

Use a new name, or inspect and update the existing home's settings manually.

## API request returns HTTP 401 or 403

Check that:

- the key belongs to the intended service/project;
- it has not expired or been revoked;
- the base URL is correct;
- the service accepts bearer authentication;
- VPN or institutional-network requirements are satisfied.

Replace the stored key with `codex-home set-key NAME`. Never print the key to
debug it.

## `/models` is 404 or contains no IDs

Model listing is a discovery convenience, not a Codex requirement. Use the
provider's exact documented model/deployment ID and test Codex directly. Some
direct Azure resources do not expose an OpenAI-style bearer-authenticated
`/models` route.

## Model listing works but Codex fails on `/responses`

The gateway may support models or Chat Completions without implementing the
Responses API. Current Codex custom providers require `wire_api = "responses"`.
Ask the provider whether the chosen route/model supports streaming Responses
and tool calls.

## Model or deployment not found

Do not substitute a public model name for a gateway-specific ID. Rerun:

```bash
./bin/codex-home models NAME
```

For Azure, check whether `model` must be a deployment name and whether the
configured `api-version` is valid for that resource.

## A subscription identity opens the wrong account

The local name does not verify the browser-selected workspace. Reauthenticate
only that home:

```bash
./bin/codex-home run work logout
./bin/codex-home login work
```

Then use `/status` in a CLI session launched with `codex-home run work`.

## A skill was skipped

`share-skills` found an existing target with the same name and refused to
overwrite it. Compare the local and shared versions. Keep the local skill,
or move it to a backup and rerun the command. See [Sharing skills](skills.md).

## The test suite reports a missing command

Install the named prerequisite and rerun the suite. The default tests require
`bash`, `direnv`, `expect`, and `jq`; see [Installation](../INSTALLATION.md).
The production helper also uses `curl` for model discovery and Codex for login,
diagnostics, and sessions.

## Generated project paths no longer exist

The `.envrc` records absolute paths to the helper's directory and the selected
identity home. If either location moves, review and update the file, then
approve the change again:

```bash
direnv allow "/path/to/project"
```

Reinstall the Finder app after moving or updating the helper so its bundled
copy is current.

## Changing or removing a project context is refused

`project-change` and `project-reset` act only on a complete, untracked pair of
files that still exactly matches a template generated by this helper. They
refuse modified, tracked, incomplete, or symlinked setups so custom or shared
project configuration is not overwritten.

Inspect the files and Git state, then either restore the generated pair or
follow the manual steps in
[Project and VS Code integration](projects-vscode.md#manual-recovery-for-a-custom-or-shared-setup).

## Strict configuration validation

Run:

```bash
./bin/codex-home doctor NAME
```

The doctor checks more than TOML parsing, so missing subscription credentials
or restricted network access may produce additional failures. It may contact
Codex update services and the configured provider.

The default tests run offline. They check generated files and reject accidental
`codex` or live `curl` calls. They do not test a live provider:

```bash
./tests/test.sh
```

Maintainers can additionally run the Codex `config.load` checks with synthetic
credentials and endpoints:

```bash
CODEX_CONTEXTS_LIVE_TESTS=1 ./tests/test.sh
```

That opt-in mode can make network requests. Run it only when outbound checks
are acceptable; it is not required for an ordinary installation.
