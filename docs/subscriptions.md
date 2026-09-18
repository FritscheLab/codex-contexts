# Subscription identities

Use `create-subscription` to keep each ChatGPT account or workspace login in
its own `CODEX_HOME`. You can create as many identities as you need, including
several with the same subscription type.

Choose names you will recognize, such as `personal`, `work`, or `edu`. These
are local labels: the helper cannot check which plan or workspace you sign in to.

For a U-M GPT API key, follow the [U-M GPT gateway setup](umgpt.md). Toolkit
API usage has [separate charges](umgpt.md#costs-and-spending-controls).

## Choose clear local names

`default` is reserved for the existing `~/.codex` home. The helper never
creates or rewrites that home.

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

Each identity keeps file-backed credentials in a different directory:

```text
~/.codex/auth.json
~/.codex-homes/personal/auth.json
~/.codex-homes/work/auth.json
~/.codex-homes/edu/auth.json
```

`auth.json` stores credentials in plain text. Keep each identity home private
and sign in separately on each computer.

## Verify each identity

Check the identity's files without printing a token:

```bash
./bin/codex-home show personal
./bin/codex-home show work
./bin/codex-home doctor work
```

`show` reports whether `auth.json` exists. `doctor` checks the configuration
and may contact network services. To confirm the account or workspace, start
a Codex session:

```bash
./bin/codex-home run work
```

Use `/status` and compare it with the identity name shown by the launcher.
`codex-home run` keeps **[CODEX: NAME]** in the terminal tab/window title.
In VS Code, check the window title as well as the status-bar color.

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

## Why Codex config profiles are not used

Codex config profiles change settings within a single `CODEX_HOME` and share
its cached login. Separate homes keep each account's credentials, sessions,
logs, skills, and other files apart. They do not isolate processes or provide
a security sandbox.

## Next steps

To use the same personal skills in every identity, run:

```bash
./bin/codex-home share-skills-all
```

Then [assign an identity to a project](projects-vscode.md).
