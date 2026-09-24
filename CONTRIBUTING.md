# Contributing

Contributions that make identity selection safer, clearer, or more portable are
welcome. Please keep changes focused and avoid adding credential storage or
provider-specific assumptions to the common workflow.

## Before opening an issue or pull request

- Never include credentials, access tokens, authentication files, private
  research data, participant data, or unredacted logs.
- Report a suspected vulnerability privately according to
  [SECURITY.md](SECURITY.md), not in a public issue.
- Search existing issues and test the current `main` branch when practical.

## Development setup

Follow [INSTALLATION.md](INSTALLATION.md), then run:

```bash
./tests/test.sh
```

Keep the helper compatible with Bash 3.2, including the system Bash on macOS.
The default tests must run without credentials or a live provider.

For focused checks, run `bash tests/identity-config.sh` for malformed defaults,
large configurations, and model-request validation. On macOS,
`bash tests/macos-open-with.sh` checks Finder app installation failures and
backup recovery using temporary apps and intercepted registration calls. Both
are included in `./tests/test.sh`.

The [CI workflow](.github/workflows/ci.yml) runs offline tests with command
mocks on Linux and macOS. It does not install Codex or validate configuration
against a real Codex release. With Codex installed, you can opt into doctor
checks that may contact configured services:

```bash
CODEX_CONTEXTS_LIVE_TESTS=1 ./tests/test.sh
```

Run these checks when assessing compatibility with a Codex release; its settings
and provider support can change.

## Making a change

1. Create a short-lived branch from `main`.
2. Add or update regression tests for behavior changes.
3. Update user documentation when commands, generated files, risks, or
   prerequisites change.
4. Run the test suite and Bash syntax checks locally:

   ```bash
   for script in bin/* tests/*.sh; do
     bash -n "$script"
   done
   ./tests/test.sh
   ```

5. Open a pull request explaining what changes for users, how you tested it,
   and any remaining limits. Use synthetic examples and remove sensitive
   information from logs.

For a new API provider or model path, document the exact provider, protocol,
model, authentication method, and tested tool behavior. A successful model
listing or plain-text response is not enough to establish full Codex
compatibility.

## Writing documentation

Give each procedure one maintained home. Other pages can summarize its purpose
and link to it; repeat a command only when readers need it to finish the current
task.

| Content | Maintained home |
|---|---|
| Orientation and guide choices | `README.md` |
| Prerequisites, installation, and updates | `INSTALLATION.md` |
| Identity creation and provider-specific setup | `docs/subscriptions.md`, `docs/api-providers.md`, `docs/umgpt.md` |
| Project setup and terminal/VS Code use | `docs/projects-vscode.md` |
| Model comparison and saved settings | `MODELS.md` |
| Model sources, catalog behavior, and picker recovery | `docs/model-reference.md` |
| Command syntax and identity verification | `docs/commands.md` |
| Symptom lookup | `docs/troubleshooting.md` |
| Finder setup and menu cleanup | `docs/macos-open-with.md` |
| Removing a folder's context | `docs/remove-folder-context.md` |

Write for someone completing a task: give the action, expected result, and a
recovery link. Keep essential warnings beside the affected action. Use
**identity** for a named account/provider configuration, **home** for its
`CODEX_HOME` directory, and **project context** for a project's identity selection.
Use preferred command names in tutorials; keep old names in compatibility notes.

When moving a section, update internal links and leave a useful destination at
its old anchor. Check the Markdown links and Mermaid diagrams with the
[documentation CI checks](.github/workflows/ci.yml), and walk through the changed
reading path. Compare helper examples with `./bin/codex-home help` and the
implementation. Verify changed upstream claims against current official sources.
If a change affects the printable cheatsheet, update its source and inspect the
rebuilt PDF as described below.

## Update the U-M GPT model snapshot

The checked-in snapshot is a dated record for review, not a runtime catalog.
With a configured, scoped `umgpt` identity and stored key, regenerate it from
the repository root with:

```bash
./bin/codex-home snapshot-umgpt-models umgpt docs/umgpt-models-snapshot.md
```

Do not edit the generated file manually. Review the date, source, model-ID
changes, and classifications before committing it. Results are specific to
the credential used; appearance in the snapshot does not establish Codex
compatibility or institutional approval. The helper never reads this file at
runtime.

## Update the printable cheatsheet

Edit [docs/build-cheatsheet.py](docs/build-cheatsheet.py), then rebuild the PDF
in a Python environment with ReportLab installed:

```bash
python3 docs/build-cheatsheet.py
```

Keep it to two pages and inspect both pages after rebuilding. Command text
should remain selectable and fit without clipping.
