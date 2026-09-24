# Subscription identities

Create a named **identity** for each ChatGPT account or workspace login. Each
identity stores its configuration and login in a separate **home**
(`CODEX_HOME`). Several identities can use the same subscription type.

Run the examples below from the clone directory after completing
[Installation steps 1–3](../INSTALLATION.md#1-install-prerequisites).

For a U-M GPT API key, follow the [U-M GPT gateway setup](umgpt.md). Toolkit
API usage has [separate charges](umgpt.md#costs-and-spending-controls).

## Choose clear local names

Choose names you will recognize, such as `personal`, `work`, or `edu`. They
appear in window titles and project files, so avoid personal names, study
identifiers, and other sensitive details. These are local labels; the helper
cannot check which plan or workspace you sign in to.

`default` is reserved for the existing `~/.codex` home. Identity-creation
commands do not overwrite it or any other existing identity.

Create an identity and sign in:

```bash
./bin/codex-home create-subscription personal
./bin/codex-home login personal
```

Check the account and workspace in the browser before approving each login.
Codex uses the account you select there, regardless of the local identity name.

Each identity created by `create-subscription` configures
`cli_auth_credentials_store = "file"`, normally caching its login in its own
directory:

```text
~/.codex-homes/personal/auth.json
```

`auth.json` stores credentials in plain text. Keep each identity home private
and sign in separately on each computer. The `default` identity retains its
existing credential-storage settings.
Administrator-enforced authentication and storage policies still apply; the
helper cannot override them. See [OpenAI's credential-storage guidance](https://learn.chatgpt.com/docs/auth#credential-storage).

## Verify each identity

Follow [Check the selected identity](commands.md#check-the-selected-identity)
for the CLI or VS Code. File presence and window labels alone do not verify
the account. If configuration checks fail, use
[Troubleshooting](troubleshooting.md).

## Add or separate more subscriptions

Repeat the same two commands with a different name for each account or
workspace, for example:

```bash
./bin/codex-home create-subscription work
./bin/codex-home login work
```

Names such as `business-client-a` and `business-client-b` can distinguish
consulting accounts. Verify each login before assigning it to a project.

## Correct a login made with the wrong account

Log out of the affected identity and sign in again:

```bash
./bin/codex-home run work logout
./bin/codex-home login work
```

This does not log out `default`, `personal`, `edu`, or any other separate
identity. Repeat the [identity checks](#verify-each-identity) after signing in.

## Identity homes and config profiles

Codex config profiles change settings within a single `CODEX_HOME` and share
its cached login. Separate homes keep their credentials, sessions, logs, and
home-local files apart. Codex can also load skills from repository, global
user, administrator, and bundled locations; see [skill discovery boundaries](skills.md#skill-discovery-boundaries).
Separate homes do not isolate processes or provide a security sandbox.

## Next steps

Next, [assign the verified identity to a project](projects-vscode.md).

To reuse personal skills from `~/.codex/skills`, follow
[Sharing skills](skills.md).
