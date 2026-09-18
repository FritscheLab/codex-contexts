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

Generated configuration has been checked with Codex CLI 0.145.0. Rerun the
tests after updating Codex because its settings and provider support can change.

## Making a change

1. Create a short-lived branch from `main`.
2. Add or update regression tests for behavior changes.
3. Update user documentation when commands, generated files, risks, or
   prerequisites change.
4. Run the test suite and Bash syntax checks locally:

   ```bash
   bash -n bin/codex-home bin/install-macos-open-with tests/test.sh
   ./tests/test.sh
   ```

5. Open a pull request explaining what changes for users, how you tested it,
   and any remaining limits. Use synthetic examples and remove sensitive
   information from logs.

For a new API provider or model path, document the exact provider, protocol,
model, authentication method, and tested tool behavior. A successful model
listing or plain-text response is not enough to establish full Codex
compatibility.

## Update the printable cheatsheet

Edit [docs/build-cheatsheet.py](docs/build-cheatsheet.py), then rebuild the PDF
in a Python environment with ReportLab installed:

```bash
python3 docs/build-cheatsheet.py
```

Keep it to two pages and inspect both pages after rebuilding. Command text
should remain selectable and fit without clipping.
