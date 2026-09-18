# Security policy

This file explains how to report a vulnerability in this repository. For the
tool's credential storage, limits, and data-handling guidance,
see [Security model](docs/security.md).

## Supported versions

Security fixes are made on the latest commit of `main`. Supported tagged
release lines, when applicable, are listed here.

| Version | Supported |
|---|---|
| Latest `main` | Yes |
| Older commits | No |

## Report a vulnerability privately

Use the repository's
[private vulnerability reporting form](https://github.com/FritscheLab/codex-contexts/security/advisories/new).
If private reporting is unavailable, email `larsf@umich.edu` with the subject
`codex-contexts security report`. Do not open a public issue for an unpatched
vulnerability.

Include only the information needed to reproduce and assess the problem:

- affected commit or release;
- operating system, shell, and relevant tool versions;
- a minimal, sanitized reproduction;
- expected and observed behavior;
- likely impact; and
- any suggested mitigation.

Do not send real credentials, tokens, login files, private research data,
participant data, or sensitive logs. Replace secrets and identifying values
with synthetic placeholders. If a sensitive artifact is essential to the
investigation, first ask the maintainer to arrange an approved transfer method.

The maintainers aim to acknowledge a complete report within five business days
and provide an initial status update within ten business days. These are goals,
not guarantees; investigation and coordinated disclosure may take longer.

## Scope

Please report issues such as:

- unintended disclosure or persistence of credentials;
- command, shell, TOML, or environment-variable injection;
- unsafe permissions on generated identity files;
- cross-identity credential or session leakage; and
- generated files that silently select a different identity or provider.

Provider outages, provider account recovery, upstream Codex vulnerabilities,
and questions about whether a provider is approved for particular research data
are outside this repository's direct control. Report upstream vulnerabilities
to the affected provider and follow your organization's data-governance process.

Please allow time for a fix and coordinated disclosure before publishing an
in-scope vulnerability.
