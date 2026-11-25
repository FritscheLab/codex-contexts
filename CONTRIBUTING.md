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

Follow the installation guide, including `expect` for the offline suite.
[Installation](INSTALLATION.md#3-clone-and-validate)

Run these commands from the clone.

```bash
for script in bin/* libexec/*.sh tests/*.sh; do bash -n "$script"; done
./tests/test.sh
```

Use Bash 3.2-compatible syntax and Python 3.11+ with the standard library.
The default suite runs without credentials or a live provider.

`bin/codex-home` dispatches commands to these libraries.

| Behavior | Source |
|---|---|
| Accounts, credentials, permissions, and CLI launch | `libexec/identities.sh` |
| Model scopes, defaults, discovery, and catalogs | `libexec/models.sh` |
| Project files, approval, and selection checks | `libexec/projects.sh` |
| VS Code launch | `libexec/vscode.sh` |
| macOS apps and shared bundle operations | `libexec/macos.sh`, `libexec/macos_bundles.py` |
| TOML validation and credential/environment boundary | `libexec/codex_contexts.py` |

The CI workflow runs the offline suite on Linux and macOS and verifies the
generated settings, identity homes, tool calls, and sandbox behavior with a
pinned native Codex and a loopback server. To check a locally installed release,
run `python3 -I tests/native-codex.py`. Add `--codex /absolute/path/to/codex`
to check another binary, including one bundled with an IDE. [CI workflow](.github/workflows/ci.yml)

To opt into tests that contact configured services, run the suite with
`CODEX_CONTEXTS_LIVE_TESTS=1`.

## Making a change

1. Create a short-lived branch from `main`.
2. Add or update regression tests for behavior changes.
3. Update the affected guide and check its commands, warnings, and links.
4. Run the [development checks](#development-setup).
5. Open a pull request explaining what changes for users, how you tested it,
   and any remaining limits. Use synthetic examples in test logs.

For a new API provider or model path, document the exact provider, protocol,
model, and authentication method. Verify a tool call as well as text output.
[API compatibility test](docs/api-providers.md#validate-compatibility)

## Update model availability, prices, and benchmarks

Update the [comparison table](docs/model-reference.md#prices-and-limits) and
[CSV](docs/data/model-benchmarks.csv) together. Record Toolkit prices and their
date, the benchmark version and date, and the evaluator's effort and any
fallback. Leave unavailable scores blank in the CSV.

For Toolkit ePHI status, match each model ID to the ITS approval column and
record the check date and source separately from the price and benchmark date.
[Toolkit model approvals](https://its.umich.edu/computing/ai/pricing#u-m-gpt-toolkit)

### Update the U-M GPT model snapshot

From the repository root, use a configured `umgpt` identity with a Toolkit key.

```bash
./bin/codex-home snapshot-umgpt-models umgpt docs/umgpt-models-snapshot.md
```

Review the date, source, and ID classifications in the generated listing.

## Update the printable cheatsheet

Edit the source and rebuild in a Python environment with ReportLab installed.
[Cheatsheet source](docs/build-cheatsheet.py)

```bash
python3 docs/build-cheatsheet.py
```

Keep it to two pages and inspect both pages after rebuilding. Command text
should remain selectable and fit without clipping.
