#!/usr/bin/env bash
# Exercise the shared app resource layout without launching a GUI or provider.
set -euo pipefail
PACKAGE_TEST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PACKAGE_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-package-test.XXXXXX")"
trap 'rm -rf -- "$PACKAGE_TEST_ROOT"' EXIT
export CODEX_HOMES_ROOT="$PACKAGE_TEST_ROOT/homes"
unset CODEX_HOME CODEX_IDENTITY CODEX_UMGPT_MODELS_FILE
source "$PACKAGE_TEST_REPO/bin/codex-home"
fail() { printf 'Packaging test failure: %s\n' "$*" >&2; exit 1; }

create_api source-api https://provider.example.test/v1 model-a PACKAGE_TEST_KEY >/dev/null
printf 'PACKAGE_TEST_KEY="synthetic-source-key"\n' >"$CODEX_HOMES_ROOT/source-api/api-key.env"

contents="$PACKAGE_TEST_ROOT/quoted bundle ' [x].app/Contents"
macos_bundle_launcher "$contents"
bundled="$contents/Resources/codex-home"
"$bundled" create-subscription package-sub >/dev/null
"$bundled" create-api package-api https://provider.example.test/v1 model-a PACKAGE_TEST_KEY >/dev/null
"$bundled" create-umgpt gpt-4.1 package-campus >/dev/null
"$bundled" set-sandbox package-sub read-only >/dev/null
"$bundled" show source-api >"$PACKAGE_TEST_ROOT/source-from-bundle"
grep -Fq 'PACKAGE_TEST_KEY' "$PACKAGE_TEST_ROOT/source-from-bundle" || fail 'bundle could not read an identity created from the clone'
project="$PACKAGE_TEST_ROOT/project with spaces"
mkdir "$project"
"$bundled" project package-api "$project" >/dev/null
grep -Fq "PATH_add" "$project/.envrc" || fail 'bundled project setup failed'
printf 'PACKAGE_TEST_KEY="synthetic-package-key"\n' >"$CODEX_HOMES_ROOT/package-api/api-key.env"
python3 -I - "$CODEX_HOMES_ROOT/package-api" "$contents/Resources" <<'PY'
from pathlib import Path
import subprocess, sys, tomllib
home, resources = map(Path, sys.argv[1:])
provider = tomllib.loads((home / "config.toml").read_text())["model_providers"]["package-api"]
auth = provider["auth"]
assert Path(auth["args"][1]).is_relative_to(resources.resolve())
token = subprocess.check_output([auth["command"], *auth["args"]], text=True, timeout=10)
assert token.strip() == "synthetic-package-key"
PY

# Module-only changes must refresh an identity handler's packaged-code hash.
before="$(macos_data_helper fingerprint "$contents/Resources/libexec")"
printf '\n# packaging fixture\n' >>"$contents/Resources/libexec/projects.sh"
after="$(macos_data_helper fingerprint "$contents/Resources/libexec")"
[[ "$before" != "$after" ]] || fail 'module change did not affect resource fingerprint'

mv "$contents/Resources/libexec/projects.sh" "$PACKAGE_TEST_ROOT/missing-projects.sh"
if "$bundled" help >"$PACKAGE_TEST_ROOT/output" 2>&1; then
  fail 'incomplete bundled installation was accepted'
fi
grep -Fq 'missing library' "$PACKAGE_TEST_ROOT/output" || fail 'missing-resource failure was not explained'
printf 'Packaging tests passed.\n'
