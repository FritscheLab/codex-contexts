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
export HOME="$CLI_TEST_ROOT/home"
export CODEX_UMGPT_MODELS_FILE="$CLI_TEST_ROOT/models.toml"
export CLI_TEST_OUTPUT="$CLI_TEST_ROOT/launched.json"
export CODEX_CONTEXTS_ENV_ALLOW='CLI_TEST_OUTPUT CLI_TEST_EXIT'
unset CODEX_HOME CODEX_IDENTITY DIRENV_DIFF DIRENV_DIR DIRENV_FILE DIRENV_WATCHES

fail() { printf 'CLI launch test failure: %s\n' "$*" >&2; exit 1; }

# Use a closed PATH: neither a real installation nor the main suite's blocking
# Codex mock may satisfy discovery.
mkdir -p "$HOME" "$CLI_TEST_ROOT/utilities" "$CLI_TEST_ROOT/.lmstudio/bin" \
  "$CLI_TEST_ROOT/working" "$CLI_TEST_ROOT/later" "$CLI_TEST_ROOT/broken"
for utility in bash basename cat cmp dirname grep python3 sed tr; do
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

"$CLI_TEST_TOOL" create-api api https://provider.example.test/v1 synthetic-model CLI_API_KEY >/dev/null
reject_launch 'run: codex-home set-key api' "$CLI_TEST_WORKING_PATH" run api

# The native -C option determines which project's generated selection applies.
academic_project="$CLI_TEST_ROOT/academic project"
personal_project="$CLI_TEST_ROOT/personal project"
mkdir -p "$academic_project" "$personal_project"
"$CLI_TEST_TOOL" create-subscription personal >/dev/null
"$CLI_TEST_TOOL" project academic "$academic_project" >/dev/null
"$CLI_TEST_TOOL" project personal "$personal_project" >/dev/null
(
  cd "$academic_project"
  export CODEX_IDENTITY=academic CODEX_HOME="$CODEX_HOMES_ROOT/academic"
  for option in -C --cd; do
    reject_launch 'project selects personal' "$CLI_TEST_WORKING_PATH" run "$option" "$personal_project"
    reject_launch 'project selects personal' "$CLI_TEST_WORKING_PATH" run "$option=$personal_project"
  done
  reject_launch 'project selects personal' "$CLI_TEST_WORKING_PATH" run "-C$personal_project"
  reject_launch 'project selects personal' "$CLI_TEST_WORKING_PATH" run -- exec --cd "$personal_project"

  CODEX_IDENTITY=personal CODEX_HOME="$CODEX_HOMES_ROOT/personal" PATH="$CLI_TEST_WORKING_PATH" \
    "$CLI_TEST_TOOL" run -C "$personal_project" >/dev/null 2>&1
  python3 -I - "$CLI_TEST_OUTPUT" "$personal_project" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["args"] == ["-C", sys.argv[2]], data
assert data["identity"] == "personal", data
PY

  # Explicit selection is an override. The native delimiter also stops flag parsing.
  assert_launch 0 run -C "$personal_project"
  PATH="$CLI_TEST_WORKING_PATH" "$CLI_TEST_TOOL" run -- -- "-C$personal_project" >/dev/null 2>&1
  python3 -I - "$CLI_TEST_OUTPUT" "$personal_project" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["args"] == ["--", "-C" + sys.argv[2]], data
assert data["identity"] == "academic", data
PY
)

# A native default home can already be in use without a settings file.
"$CLI_TEST_TOOL" list | grep -F 'not initialized' >/dev/null || fail 'missing default not labeled'
mkdir -p "$HOME/.codex"
"$CLI_TEST_TOOL" list --names | grep -Fx 'default' >/dev/null || fail 'config-free default not listed'
"$CLI_TEST_TOOL" show default | grep -F 'inherited (Codex defaults)' >/dev/null || fail 'default settings not shown'
PATH="$CLI_TEST_WORKING_PATH" "$CLI_TEST_TOOL" run default login status >/dev/null 2>&1
python3 -I - "$CLI_TEST_OUTPUT" "$HOME/.codex" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data == {"args": ["login", "status"], "home": sys.argv[2], "identity": "default"}, data
PY
[[ ! -e "$HOME/.codex/config.toml" ]] || fail 'launch unexpectedly wrote default settings'
"$CLI_TEST_TOOL" set-sandbox default inherit >/dev/null
[[ ! -e "$HOME/.codex/config.toml" ]] || fail 'inheriting settings wrote default config'
"$CLI_TEST_TOOL" set-sandbox default read-only >/dev/null
grep -Fxq 'sandbox_mode = "read-only"' "$HOME/.codex/config.toml" || fail 'could not write explicit default settings'

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
