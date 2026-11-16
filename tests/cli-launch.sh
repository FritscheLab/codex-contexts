#!/usr/bin/env bash
# Offline CLI discovery and launch regressions; never invoke an installed Codex.
set -euo pipefail

CLI_TEST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$CLI_TEST_REPO/tests/common.sh"
CLI_TEST_TOOL="$(resolve_codex_home_tool "$CLI_TEST_REPO/bin")"
CLI_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-cli-launch.XXXXXX")"
trap 'rm -rf -- "$CLI_TEST_ROOT"' EXIT
CLI_TEST_ROOT="$(cd "$CLI_TEST_ROOT" && pwd -P)"
export CODEX_HOMES_ROOT="$CLI_TEST_ROOT/homes"
export CODEX_UMGPT_MODELS_FILE="$CLI_TEST_ROOT/models.toml"
export CLI_TEST_OUTPUT="$CLI_TEST_ROOT/launched.json"
export CODEX_CONTEXTS_ENV_ALLOW='CLI_TEST_OUTPUT CLI_TEST_EXIT'
unset CODEX_HOME CODEX_IDENTITY DIRENV_DIFF DIRENV_DIR DIRENV_FILE DIRENV_WATCHES

fail() { printf 'CLI launch test failure: %s\n' "$*" >&2; exit 1; }

# Use a closed PATH: neither a real installation nor the main suite's blocking
# Codex mock may satisfy discovery. Keep the reported last-candidate scenario.
mkdir -p "$CLI_TEST_ROOT/utilities" "$CLI_TEST_ROOT/.lmstudio/bin" \
  "$CLI_TEST_ROOT/working" "$CLI_TEST_ROOT/later" "$CLI_TEST_ROOT/broken"
for utility in bash basename dirname python3 sed tr; do
  ln -s "$(command -v "$utility")" "$CLI_TEST_ROOT/utilities/$utility"
done
CLI_TEST_MISSING_PATH="$CLI_TEST_ROOT/utilities:$CLI_TEST_ROOT/.lmstudio/bin"

"$CLI_TEST_TOOL" create-subscription academic >/dev/null

reject_launch() {
  local diagnostic="$1" launch_path="$2"
  shift 2
  rm -f "$CLI_TEST_OUTPUT"
  if PATH="$launch_path" "$CLI_TEST_TOOL" "$@" \
    >"$CLI_TEST_ROOT/output" 2>"$CLI_TEST_ROOT/error"; then
    fail "accepted a failed CLI launch: $*"
  fi
  grep -Fq -- "$diagnostic" "$CLI_TEST_ROOT/error" || {
    cat "$CLI_TEST_ROOT/error" >&2
    fail "missing diagnostic: $diagnostic"
  }
  [[ ! -e "$CLI_TEST_OUTPUT" ]] || fail 'failed discovery invoked Codex'
}

for command in login run doctor; do
  reject_launch "Codex CLI executable 'codex' was not found on PATH" \
    "$CLI_TEST_MISSING_PATH" "$command" academic
  grep -Fq 'codex --version' "$CLI_TEST_ROOT/error" || \
    fail 'missing CLI diagnostic omitted the terminal verification command'
  grep -Fq 'INSTALLATION.md#1-install-prerequisites' "$CLI_TEST_ROOT/error" || \
    fail 'missing CLI diagnostic omitted the installation reference'
  if grep -Fq '.lmstudio/bin/codex' "$CLI_TEST_ROOT/error"; then
    fail 'missing CLI diagnostic blamed the last PATH candidate'
  fi
done

cat >"$CLI_TEST_ROOT/working/codex" <<'EOF'
#!/usr/bin/env python3
import json, os, sys
with open(os.environ["CLI_TEST_OUTPUT"], "w") as handle:
    json.dump({"args": sys.argv[1:], "home": os.environ["CODEX_HOME"],
               "identity": os.environ["CODEX_IDENTITY"]}, handle)
raise SystemExit(int(os.environ.get("CLI_TEST_EXIT", "0")))
EOF
chmod +x "$CLI_TEST_ROOT/working/codex"
# A second usable executable must not override the first command on PATH.
printf '%s\n' '#!/bin/sh' 'exit 98' >"$CLI_TEST_ROOT/later/codex"
chmod +x "$CLI_TEST_ROOT/later/codex"
CLI_TEST_WORKING_PATH="$CLI_TEST_ROOT/working:$CLI_TEST_ROOT/later:$CLI_TEST_MISSING_PATH"

assert_launch() {
  local expected_status="$1" command="$2" actual_status
  shift 2
  rm -f "$CLI_TEST_OUTPUT"
  if CLI_TEST_EXIT="$expected_status" PATH="$CLI_TEST_WORKING_PATH" \
    "$CLI_TEST_TOOL" "$command" academic "$@" \
    >"$CLI_TEST_ROOT/output" 2>"$CLI_TEST_ROOT/error"; then
    actual_status=0
  else
    actual_status=$?
  fi
  [[ "$actual_status" -eq "$expected_status" ]] || {
    cat "$CLI_TEST_ROOT/error" >&2
    fail "$command changed the Codex exit status"
  }
  python3 -I - "$CLI_TEST_OUTPUT" "$CODEX_HOMES_ROOT/academic" "$command" "$@" <<'PY'
import json, sys
path, home, command, *arguments = sys.argv[1:]
data = json.load(open(path))
expected = {"login": ["login"], "doctor": ["--strict-config", "doctor", "--summary"]}
assert data["args"] == expected.get(command, arguments), data
assert data["home"] == home and data["identity"] == "academic", data
PY
}

assert_launch 0 login
assert_launch 37 run --model synthetic-model 'prompt with spaces' 'literal $HOME'
assert_launch 0 doctor

# An executable script can exist while its interpreter does not. Report that
# installation failure separately from an absent command on PATH.
printf '#!%s\n' "$CLI_TEST_ROOT/absent-interpreter" >"$CLI_TEST_ROOT/broken/codex"
chmod +x "$CLI_TEST_ROOT/broken/codex"
reject_launch "could not start Codex CLI at $CLI_TEST_ROOT/broken/codex" \
  "$CLI_TEST_ROOT/broken:$CLI_TEST_MISSING_PATH" login academic
grep -Fq 'check its interpreter or reinstall the CLI' "$CLI_TEST_ROOT/error" || \
  fail 'broken executable diagnostic omitted interpreter guidance'
if grep -Fq "was not found on PATH" "$CLI_TEST_ROOT/error"; then
  fail 'an existing executable was reported as missing from PATH'
fi

printf 'CLI launch tests passed.\n'
