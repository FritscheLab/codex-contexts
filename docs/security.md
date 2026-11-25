# Permissions and credentials

Account selection and command permissions are separate controls.

## What an approval allows

The helper starts local programs with your user permissions. Inspect the
checkout before running it. Even help and tests execute code from the checkout.
[Review the checkout](../INSTALLATION.md#review-the-checkout-before-running-it)

| Action or prompt | What you grant |
|---|---|
| Run the helper, installer, or tests yourself | The script can use the files, credentials, and network access available to your shell. The installer's Finder app bundles helper code from this checkout. |
| `direnv allow` or Finder **Approve & Open** | Direnv can run the project's `.envrc` as your user when it loads the folder, including other files that `.envrc` loads. This runs before the editor launch checks and outside the Codex command sandbox. |
| macOS folder-access prompt | macOS can grant the named application access to the protected location in the dialog. Check the app and location before allowing access. |
| VS Code **Workspace Trust** | VS Code can enable workspace tasks, settings, and extensions that Restricted Mode limits. Review the workspace and the extensions you run. [VS Code Workspace Trust](https://code.visualstudio.com/docs/editing/workspaces/workspace-trust) |
| Codex command approval | The requested command or access can proceed under the scope shown in the prompt. For an execution outside the sandbox, the command may use your normal OS permissions. [Codex sandbox and approvals](https://learn.chatgpt.com/docs/sandboxing#configure-defaults) |

Read `.envrc` as text before approving it. The generated version selects the
identity and home, adds the helper's directory to `PATH`, and watches settings
files. Inspect those paths and any code that runs or loads another file. An
approval for `.envrc` can outlast changes to the code it points to. Use
`direnv deny /path/to/project/.envrc` to revoke approval for future loads.
Close affected editor and agent sessions to clear their loaded environment.
[direnv command reference](https://direnv.net/man/direnv.1.html#commands)

### Before you approve a Codex command

Check the exact command and working directory. Read scripts it invokes and
inspect each part of chained commands. Check what it will read, write, or
delete, what credentials it can use, and where any network requests or uploads
will go. For a command that downloads and runs code, ask to review the file
first. Choose a one-time approval when it fits. Read any proposed reusable rule
as permission for future matching commands.
[Codex command rules](https://learn.chatgpt.com/docs/agent-configuration/rules)

If the action is unclear, decline and ask Codex for a plain-language explanation.
For example, ask **"Show the exact command and target paths, explain why it
needs extra access, and give me a read-only preview if possible."** Commands
that already fit the active permissions can run without asking. Inside a
writable workspace that can include replacing or deleting files.

### Before you give an agent access

Use a folder with only the files the task needs and check what the agent can
read outside that folder. Review project instructions, skills, and tool
configuration before giving the agent access. Even in `read-only` mode, prompts,
file excerpts, and tool output can be sent to the selected model provider.
Connected tools and services have their own permissions and can act using the
accounts you connect. Review the service, account, data, and actions before
connecting it. Follow the data rules for your provider and workflow.

For projects with a provider or model restriction, choose the helper launch
each time. Plain `codex` and regular VS Code opens skip the helper's checks.
[Launch and verify an ePHI-restricted project](umgpt.md#check-data-permissions-first)

## Before running a removal command

Check the target folder and take a backup of any files you may need. These
commands take action when run from the terminal.

| Command | Effect |
|---|---|
| `codex-home project-change NAME DIR` | Replaces the supported generated context in `DIR` and revokes its direnv approval. Review the replacement before approving it. |
| `codex-home project-reset DIR` | Permanently removes the recognized generated `.envrc` and workspace, revokes approval, and removes eligible helper-owned Git exclusions. [Removal guide](remove-folder-context.md) |
| `codex-home reset-umgpt-defaults` | Overwrites personal U-M model defaults and picker order with the repository template, then tries to apply them to the standard identities. [Model settings](model-reference.md#other-model-settings) |
| `./bin/uninstall-macos-open-with` | Unregisters and moves owned Finder integration bundles to Trash. [Uninstall scope](macos-open-with.md#uninstall-the-finder-integration) |
| `./bin/cleanup-macos-open-with --apply` | Scans again and permanently deletes eligible generated bundles and old backups. Run and read the preview before adding `--apply`. [Cleanup scope](macos-open-with.md#clean-up-generated-apps) |

## Optional native sandbox

| What do you need? | Set this default |
|---|---|
| Edit and test a project | `codex-home set-sandbox work workspace-write` |
| Review with fewer write permissions | `codex-home set-sandbox work read-only` |
| Use the remaining Codex configuration | `codex-home set-sandbox work inherit` |

The two sandbox modes select `on-request` approvals with user review. Restart
the CLI or reload VS Code and start a new chat. Check `/status` and
`/permissions`, or the IDE permissions control.

`inherit` removes root `sandbox_mode`, `approval_policy`, and
`approvals_reviewer` settings; it does not restore old values or disable the
sandbox. Existing network settings and extra writable roots are preserved.
Project settings, profiles, CLI options, runtime changes, and managed policy
can affect effective permissions. These are defaults, not enforced policy.

<details>
<summary>Custom configurations and platform requirements</summary>

`set-sandbox` refuses symlinked configs, multiline root strings, and the
separate `default_permissions`/`permissions` configuration system. Edit those
manually. Nested profile and plugin settings are preserved.

The installed Codex provides enforcement. See its
[sandbox guide](https://learn.chatgpt.com/docs/sandboxing) for platform
requirements, including `bubblewrap` on Linux, and its
[configuration precedence](https://learn.chatgpt.com/docs/config-file/config-basic#configuration-precedence).

</details>

### Deny sandboxed reads of a folder

For an extra local guardrail, choose one folder on storage approved for your
restricted projects. Add its absolute path to the permission profile for your
everyday Codex identity. For plain Codex with no `CODEX_HOME` override, edit
`~/.codex/config.toml`. Put `default_permissions` above any table headers and
replace the example path with your folder's path.

```toml
default_permissions = "everyday"

[permissions.everyday]
extends = ":workspace"

[permissions.everyday.filesystem]
"/absolute/path/to/restricted" = "deny"
```

Set `extends = ":read-only"` if you work in read-only mode. If you already use a
named profile, add only the path rule to its `filesystem` table. Older
`sandbox_mode` settings can take precedence. Follow Codex's migration guidance
before switching.
[Codex permission profiles](https://learn.chatgpt.com/docs/permissions#deny-reads-with-exact-paths-or-globs) | [Migration guide](https://learn.chatgpt.com/docs/permissions#migrate-from-older-sandbox-settings)

Put a harmless `read-check.txt` in the folder. From outside the restricted
folder, in the shell you normally use for the everyday identity, try reading
it through the sandbox. Expect a permission error, then restart any open
Codex sessions to load the change.

```bash
codex sandbox /bin/cat "/absolute/path/to/restricted/read-check.txt"
```

Repeat the rule in any additional everyday homes. **If you want plain `codex`
to keep using its everyday home inside the restricted folder**, use a terminal
without the optional direnv shell hook. The hook can switch `CODEX_HOME` as
soon as you enter an approved folder. For restricted work, run
`direnv exec . codex-home run` from the approved folder, or use the
[VS Code or Finder launch](umgpt.md#check-data-permissions-first).

The rule applies to sandboxed commands using the profile. Ordinary VS Code,
other processes, and actions outside the sandbox can still read files your OS
account can access. Use an approved separate account or managed environment if
you need file isolation.

## Risks and limitations

| Control | Helps with | Does not provide |
|---|---|---|
| Separate identity homes | Accidental account and session mix-ups | Required-account enforcement across launchers, or isolation from other processes running as your OS user |
| Restricted environment and command-backed API auth | Keeping inherited credentials and new identities' keys out of the editor/command environment | Isolation from Codex itself or other same-user processes |
| Native command sandbox | Bounding model-generated command writes and networking | Isolation of the entire app, editor extensions, manual shell commands, or external services |
| HTTPS validation | Accidental plaintext provider requests | A firewall for arbitrary commands or protection from a malicious selected provider |
| Finder review and approval checks | Detecting generated-context edits before or during approval | A transactional guarantee against hostile concurrent same-user processes |

Use a separate OS account, container, or VM for untrusted code. Check which
host files and credentials are shared with that environment. Use a provider
and workflow approved for your data. [U-M data permissions](umgpt.md#check-data-permissions-first)

## Where data lives

| Data | Location |
|---|---|
| ChatGPT login | `$CODEX_HOME/auth.json` by default; optional OS keyring at creation |
| API key | `$CODEX_HOME/api-key.env` for managed command-backed auth; legacy `env_key` uses `.env` |
| Settings, sessions, logs, VS Code state | Under `$CODEX_HOME` |
| Project selection | Project `.envrc` and `.vscode/*.code-workspace`; no keys |

Keep identity homes local, private, outside Git and cloud sync. New homes and
credential files use owner-only permissions. `default` keeps its existing
credential-storage choice; managed authentication requirements still apply.
Do not put keys in command arguments, config headers, chat, issues, or logs.
Confirm the configured provider and base URL with `codex-home show NAME`
before entering a key at the hidden prompt. Treat `api-key.env` and a
file-backed `auth.json` as sensitive plaintext files. Redact diagnostics
before sharing them, including local paths and any provider response details.

## Secret exposure boundaries

The helper reads one selected key assignment as data, never shell code.
`set-key` uses a hidden prompt, mode `600`, atomic replacement, and rejects
symlinked key paths. New API identities use native command-backed auth: the
key goes to Codex through a private command's stdout, outside the editor and
generated-command environments. Codex and other processes running as your user
can still read the key file. Legacy `env_key` configurations expose the selected
key in the launched application and its children until explicitly migrated:

```bash
codex-home migrate-api-auth NAME
```

Migration updates a recognized provider and moves its valid `.env` key to
`api-key.env`, preserving the key's contents. Codex automatically exports a
home's `.env`, so managed launches refuse a leftover file. Custom settings,
conflicting files, and symlinks are refused; interrupted changes restore the
originals or retain them at a reported recovery path. Close and reopen the
identity's editor/CLI processes afterward to clear inherited keys.

New project contexts leave keys out of the surrounding shell. Use
`codex-home run` for API identities. Refresh an untouched older context with:

```bash
codex-home project-change NAME PROJECT_DIR
```

Review and reapprove the generated files. For a hand-edited context, remove
its `dotenv_if_exists` key-loading line before review and `direnv allow`.
An `.envrc` is executable code: read it before approving it.

## Environment forwarding

Forward only the exact environment variables the task needs. A process with
`SSH_AUTH_SOCK` can request authentication through your SSH agent. A forwarded
key or token can become available to the application and its child processes.
An example for a workflow that needs an SSH agent, HTTPS proxy, and certificate:

```bash
CODEX_CONTEXTS_ENV_ALLOW='SSH_AUTH_SOCK HTTPS_PROXY SSL_CERT_FILE' codex-home run work
```

Runtime/UI/toolchain variables and `LC_*` locales are retained. Unrelated
credentials are omitted. Names are space-separated; wildcards and loader
variables such as `BASH_ENV`, `PYTHONPATH`, `NODE_OPTIONS`, `LD_*`, and `DYLD_*`
are blocked. Managed command-backed keys always use `api-key.env` and are
removed from forwarded variables. Legacy/custom `env_key` configurations can
use an external key only when its exact name is opted in and no stored key exists.

Direct `codex`/`code` launches do not apply this filter. An already running
VS Code process keeps its environment; close that identity's windows before
reopening to replace it.

## Provider checks

Checks cover `openai_base_url`, `chatgpt_base_url`, and provider `base_url` and
`model_catalog_url` in saved settings, ancestor project configs, selected
profiles, and CLI overrides. Checked URLs require HTTPS; exact `localhost`,
`127.0.0.1`, and `[::1]` HTTP endpoints are allowed for local development.
Catalog request URLs may include query parameters; base URLs may not.
Model discovery ignores automatic curl configuration, does not follow
redirects, and supplies the bearer key over standard input.

U-M launches additionally reject provider-routing and custom catalog URL
overrides and validate model scope in both CLI and VS Code. Direct launches
and manual runtime changes are outside these helper checks.

## Rotation and revocation

Replace a key with `codex-home set-key NAME`, then revoke the old key at its
provider. For a ChatGPT identity, run `codex-home run NAME logout` and
`codex-home login NAME`.

Removing a [project context](remove-folder-context.md) keeps its identity
home. The helper does not delete identity homes or their credentials/history.

## Skill links

Shared skills can change behavior across every linked identity. Review their
changes and [discovery boundaries](skills.md#skill-discovery-boundaries).
