# Sharing skills across Codex homes

If you already keep personal skills in `~/.codex/skills`, the helper can link
them into each additional identity's `$CODEX_HOME/skills`. This lets you
update the source once for every linked identity. The source directory must
already exist; this command does not install or migrate skills.

The default source directory is:

```text
~/.codex/skills
```

## Populate every configured identity

```bash
./bin/codex-home share-skills-all
```

This scans the additional homes under `~/.codex-homes` and adds one symbolic
link per personal skill:

```text
~/.codex-homes/personal/skills/my-skill
  -> ~/.codex/skills/my-skill
```

Each skill gets its own link:

- updates to the source skill are available to every linked identity;
- each home retains its own `.system` directory and may contain additional
  identity-specific skills.

Run the command again after adding skills. It adds new links and leaves
correct existing links alone. Repeat this on each computer because the links
use local paths.

## Populate one identity

```bash
./bin/codex-home share-skills work
./bin/codex-home share-skills umgpt
```

To share skills from another directory, pass its path or set `CODEX_SKILLS_SOURCE`:

```bash
./bin/codex-home share-skills work /path/to/canonical/skills

export CODEX_SKILLS_SOURCE=/path/to/canonical/skills
./bin/codex-home share-skills-all
```

## Conflict behavior

If a skill with the same name already exists, the helper reports it and moves
on without replacing it. To resolve a conflict:

1. Compare the identity's skill with the source version.
2. Keep the local directory if it is intentionally different.
3. To use the shared version, move the local directory to a backup
   outside `skills`, then rerun `share-skills NAME`.

## What this command does not share

- `.system` stays managed per Codex home.
- Authentication, sessions, logs, config, and API keys stay in each identity's
  home; the command does not share them.
- Plugins and their state are not copied by this command.
- A skill installed only in another identity stays local to that identity.

To share a new skill, install or move it into the source directory, then rerun
`share-skills-all`.

## Skill discovery boundaries

These links are only this helper's sharing workflow. Codex also discovers
skills in repository `.agents/skills`, global user `$HOME/.agents/skills`,
administrator `/etc/codex/skills`, and bundled locations. Changing `CODEX_HOME`
is not a complete skill isolation boundary. The helper does not manage or
migrate `$HOME/.agents/skills`. See [OpenAI's current skill-discovery guide](https://learn.chatgpt.com/docs/build-skills#where-codex-loads-local-skills).

## Trust and updates

A linked skill uses the source's current code and instructions. Review changes
before using the skill with another account, provider, or kind of research data.
