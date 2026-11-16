# Remove Codex settings from a folder

Disconnecting a folder removes its automatic identity selection, leaving
source files, accounts, and credentials intact.

| Situation | Action |
|---|---|
| Generated files are unchanged | [Try Terminal removal](#try-removal-from-terminal) |
| Files are customized, shared, missing, or removal is refused | [Remove settings manually](#remove-the-settings-manually) |
| Only a menu entry is unwanted | [macOS launcher cleanup](macos-open-with.md#clean-up-generated-apps) |

## Try removal from Terminal

Save work and quit the affected identity's editor and Codex chats. From the
codex-contexts clone, run:

```bash
./bin/codex-home project-reset "/path/to/project"
```

This removes only an unchanged, untracked pair of generated `.envrc` and
workspace files, revokes direnv approval, and removes their exact local Git
exclusions. Continue to [check the result](#4-check-the-result).
If refused, use manual removal; there is no force option.

## Remove the settings manually

Keep source/data, `.git`, `.codex`, `.direnv`, the project's `.env`, unrelated
`.vscode` files, identity homes, and `vscode-user-data` intact. Skip missing
files. Do not delete directories to clear a window label.

### 1. Find and back up the affected files

Close affected sessions. Inspect `.envrc` and
`.vscode/<folder-name>.code-workspace`. Older setups may use
`.vscode/codex-context.code-workspace` or a previous folder name. Inspect
`.vscode/settings.json` or another workspace only if you merged Codex settings
there yourself. Finder's **Command-Shift-.** shows hidden files.

Copy files you will change to a private backup outside the project, recording
original paths and preserving uncommitted edits. A generated-file comment does
not prove a file is unchanged. In Git projects, check:

```bash
git -C "/path/to/project" status --short
git -C "/path/to/project" ls-files -- .envrc .vscode
```

Coordinate tracked-file changes with the team. Inspect symbolic-link targets;
do not edit through a link into shared or another project's files.

### 2. Stop loading the old environment

For this folder's own `.envrc`, run:

```bash
direnv deny "/path/to/project/.envrc"
```

If absent, skip this; do not revoke a parent folder's approval. Resolve file
access errors before editing. If direnv is unavailable, keep affected sessions
closed and review the final file before using direnv again.

### 3. Remove only the Codex settings

| File state | Action |
|---|---|
| Entirely generated, untracked, no longer needed | Move that exact file to your backup. Keep the rest of `.vscode`. |
| Customized or shared | Keep it and edit only the settings below. |
| Missing | Leave it missing. |

In a retained **`.envrc`**, remove the `CODEX_IDENTITY`/`CODEX_HOME` exports,
associated home check, identity `watch_file` calls, and Codex `log_status`.
Remove legacy `dotenv_if_exists "$CODEX_HOME/.env"` if present. Remove the
helper's `PATH_add` only if nothing else needs it, keeping matching `if`/`fi`
blocks intact. Compare the [identity block](projects-vscode.md#existing-envrc).
Preserve other language setup, variables, paths, and unrelated `.env` loading;
check unfamiliar lines before changing them.

In a retained **workspace or `.vscode/settings.json`**, restore the prior
`window.title` or remove `[CODEX: ...]`. Restore/remove only helper-added
`workbench.colorCustomizations` entries: `statusBar.background`,
`statusBar.foreground`, `statusBar.noFolderBackground`, and
`statusBar.debuggingBackground`. Preserve other settings, folders, and tasks.
Labels alone do not select an identity.

### 4. Check the result

If `.envrc` remains, check syntax, read the complete file, and approve only the
intended commands:

```bash
bash -n "/path/to/project/.envrc"
direnv allow "/path/to/project/.envrc"
```

Skip these commands if removed. Open a fresh standalone terminal with the
direnv hook, enter the folder, and check:

```bash
direnv status
printf 'CODEX_IDENTITY=%s\nCODEX_HOME=%s\n' "${CODEX_IDENTITY-}" "${CODEX_HOME-}"
```

The folder should no longer select the removed identity, and normal project
tools should work. Open VS Code normally to check labels/settings. Review
tracked changes with `git diff`; keep backups until verified.

## The old identity still appears

| Where it appears | Check |
|---|---|
| Existing window or terminal only | Restart it; running processes retain their environment. |
| Fresh terminal | Inspect `direnv status` and shell startup files. A parent `.envrc` may select an identity; preserve shared configuration while tracing it. |
| Title/colors only | Inspect the workspace actually opened and `.vscode/settings.json`; edit only the properties in step 3. |

## Optional: tidy local Git exclusions

Stale exclusions do not activate a context. To remove them, locate and back up
the actual exclude file:

```bash
git -C "/path/to/project" rev-parse --git-path info/exclude
```

Resolve a relative result from the project folder. Remove only exact helper
patterns for files you removed; nested projects include their relative path.
Keep rules for retained files, other projects, shared `.gitignore`, and global
ignores.

## Restore your backup

Restore only your changed files/settings, preserving newer work. Read a
restored `.envrc` before `direnv allow "/path/to/project/.envrc"`, then start
a fresh editor session.

Return to [project setup](projects-vscode.md) or [troubleshooting](troubleshooting.md).
