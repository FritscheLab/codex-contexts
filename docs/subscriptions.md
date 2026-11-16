# Subscription identities

Use a separate identity for each ChatGPT account or workspace login. For a
Toolkit API key, use [U-M setup](umgpt.md) instead.

Config profiles share a home's login; use separate homes for different
accounts. Homes do not isolate processes running as your OS user. See
[permissions and credential boundaries](security.md).

## Create and sign in

Choose a recognizable label such as `personal` or `work`. Labels appear in
project files and window titles, so keep sensitive names out of them.
`default` is reserved for the existing `~/.codex` home.

```bash
./bin/codex-home create-subscription personal
./bin/codex-home login personal
```

Check the account and workspace in the browser before approving login.
The local label does not determine the account. Repeat the two commands
with another label for each additional login.

New subscription identities select file-backed credential storage
(`cli_auth_credentials_store = "file"`), normally at
`~/.codex-homes/personal/auth.json`. This file contains plaintext credentials:
keep the home private and sign in separately on each computer.
To use the OS credential store instead, create the identity with
`codex-home create-subscription personal keyring`. It requires a working
keyring and does not fall back to plaintext files. Keyring entries are scoped
to the home path; moving that home requires signing in again.
The `default` identity keeps its existing storage choice; managed
authentication/storage requirements still apply. See
[OpenAI's credential-storage guidance](https://learn.chatgpt.com/docs/auth#credential-storage).

## Verify each identity

Follow [Check the selected identity](commands.md#check-the-selected-identity)
before [assigning it to a project](projects-vscode.md).
Window labels and the presence of `auth.json` alone do not verify the account.

## Correct a login made with the wrong account

Log out of that identity, then sign in again:

```bash
./bin/codex-home run personal logout
./bin/codex-home login personal
```

Other identity homes keep their logins. Repeat the
[identity checks](commands.md#check-the-selected-identity) afterward.
