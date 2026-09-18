# Troubleshooting

## The CLI does not show the context name

Inside a configured project, launch it with `codex-home run`. To choose an
identity explicitly, use `codex-home run NAME`. The helper prints a context
banner and keeps **[CODEX: NAME]** in the terminal tab/window title. Plain
`codex` does not use this launcher label. Codex's own footer has no custom
context-name item.

If the title stays hidden, allow applications to set titles in your terminal's
settings. See [Terminal context labels](commands.md#keep-the-context-visible-in-the-terminal).

## `run` asks for a name or reports no active project context

An older helper requires `run NAME`. Update your clone and, if installed,
reinstall the Finder app once per computer; see [Updating](../INSTALLATION.md#updating-this-repository).
`command -v codex-home` shows which copy your shell uses. `rehash` alone does
not update that file, and existing projects do not need to be configured again.

The short command reads `CODEX_IDENTITY` from your shell. If it reports no
active context, check the [direnv shell hook](../INSTALLATION.md#2-enable-direnv-in-your-shell),
review and approve the project's `.envrc`, then leave and re-enter the folder.
You can also choose a context directly with `codex-home run NAME`.

## `zsh: permission denied: /path/to/project`

The project path was interpreted as a new command, usually because it was put
on a separate line. Run one complete command and quote paths containing spaces:

```bash
./bin/codex-home vscode personal "/path/to/project"
```

## VS Code CLI is not found

The helper checks `code` on `PATH` and standard macOS application paths. If
needed, open the VS Code Command Palette and run **Shell Command: Install 'code'
command in PATH**, or set:

```bash
export CODEX_VSCODE_CLI="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
```

## `project selects '', not 'NAME'`

Approve the generated `.envrc`:

```bash
direnv allow "/path/to/project"
```

If it selects a different name, inspect `.envrc`; the helper does not overwrite
an existing selection. Run `direnv reload` after editing.

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

The `.envrc` records absolute paths to this repository and the selected
identity home. If either location moved, review and update the file, then
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
