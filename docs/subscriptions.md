# Subscription identities

Use `create-subscription` to keep each ChatGPT account or workspace login in
its own `CODEX_HOME`. You can create as many identities as you need, including
several with the same subscription type.

Choose names you will recognize, such as `personal`, `work`, or `edu`. These
are local labels: the helper cannot check which plan or workspace you sign in to.

For a U-M GPT API key, follow the [U-M GPT gateway setup](umgpt.md). Toolkit
API usage has [separate charges](umgpt.md#costs-and-spending-controls).

After [installing prerequisites and cloning the repository](../INSTALLATION.md#1-install-prerequisites)
(Installation steps 1–3), run the `./bin/codex-home` examples below from the clone directory.

## Choose clear local names

`default` is reserved for the existing `~/.codex` home. Identity-creation
commands do not overwrite it or any other existing identity.

Create and sign in to as many additional identities as you need:

```bash
./bin/codex-home create-subscription personal
./bin/codex-home login personal

./bin/codex-home create-subscription work
./bin/codex-home login work

./bin/codex-home create-subscription edu
./bin/codex-home login edu
```

Check the account and workspace in the browser before approving each login.
Codex uses the account you select there, regardless of the local identity name.

Each identity created by `create-subscription` configures
`cli_auth_credentials_store = "file"`, normally caching its login in its own
directory:

```text
~/.codex-homes/personal/auth.json
~/.codex-homes/work/auth.json
~/.codex-homes/edu/auth.json
```

`auth.json` stores credentials in plain text. Keep each identity home private
and sign in separately on each computer. The `default` identity retains its
existing credential-storage settings.
Administrator-enforced authentication and storage policies still apply; the
helper cannot override them. See [OpenAI's credential-storage guidance](https://learn.chatgpt.com/docs/auth#credential-storage).

## Verify each identity

Check the identity's files without printing a token:

```bash
./bin/codex-home show personal
./bin/codex-home show work
./bin/codex-home doctor work
```

`show` reports local configuration and whether `auth.json` exists. `doctor`
checks the configuration and may contact network services. Follow the
[CLI and VS Code verification steps](commands.md#check-the-selected-identity)
to check authentication and the active model; file presence and window labels
alone do not verify the account.

## Add or separate more subscriptions

Give each Business workspace or consulting account its own label, for example:

```bash
./bin/codex-home create-subscription business-client-a
./bin/codex-home login business-client-a

./bin/codex-home create-subscription business-client-b
./bin/codex-home login business-client-b
```

Choose names that distinguish the account or workspace without exposing a
person's name, study identifier, or other sensitive detail in window titles and
generated project files.

## Correct a login made with the wrong account

Log out of the affected identity and sign in again:

```bash
./bin/codex-home run work logout
./bin/codex-home login work
```

This does not log out `default`, `personal`, `edu`, or any other separate
identity.

## Identity homes and config profiles

Codex config profiles change settings within a single `CODEX_HOME` and share
its cached login. Separate homes keep their credentials, sessions, logs, and
home-local files apart. Codex can also load skills from repository, global
user, administrator, and bundled locations; see [skill discovery boundaries](skills.md#skill-discovery-boundaries).
Separate homes do not isolate processes or provide a security sandbox.

## Next steps

Next, [assign the verified identity to a project](projects-vscode.md).

Optionally, if you already have personal skills in `~/.codex/skills`, link them
into your additional identities:

```bash
./bin/codex-home share-skills-all
```

See [Sharing skills](skills.md) for source requirements and discovery boundaries.
