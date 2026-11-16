# Permissions and credentials

Account selection and command permissions are separate controls.

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

## Risks and limitations

| Control | Helps with | Does not provide |
|---|---|---|
| Separate identity homes | Accidental account and session mix-ups | Required-account enforcement across launchers, or isolation from other processes running as your OS user |
| Restricted environment and command-backed API auth | Keeping inherited credentials and new identities' keys out of the editor/command environment | Isolation from Codex itself or other same-user processes |
| Native command sandbox | Bounding model-generated command writes and networking | Isolation of the entire app, editor extensions, manual shell commands, or external services |
| HTTPS validation | Accidental plaintext provider requests | A firewall for arbitrary commands or protection from a malicious selected provider |
| Finder review and approval checks | Detecting generated-context edits before or during approval | A transactional guarantee against hostile concurrent same-user processes |

Use a separate OS account, container, or VM for untrusted code. A sandbox that
permits reads is not a credential vault. Use a provider and workflow approved
for your data; [U-M scope labels do not establish institutional approval](umgpt.md#check-data-permissions-first).

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

Need an SSH agent, proxy, certificate path, or external secret-manager key?
Opt in to exact names:

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
