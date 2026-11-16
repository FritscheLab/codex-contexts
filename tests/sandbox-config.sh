#!/usr/bin/env bash
# Offline checks for sandbox defaults and safe handling of hand-edited configs.
set -euo pipefail

SANDBOX_TEST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$SANDBOX_TEST_REPO/tests/common.sh"
SANDBOX_TEST_TOOL="$(resolve_codex_home_tool "$SANDBOX_TEST_REPO/bin")"
SANDBOX_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-sandbox-test.XXXXXX")"
trap 'rm -rf -- "$SANDBOX_TEST_ROOT"' EXIT
export CODEX_HOMES_ROOT="$SANDBOX_TEST_ROOT/identities"

fail() { printf 'Sandbox config test failure: %s\n' "$*" >&2; exit 1; }
expect_unchanged_failure() {
  cp "$sandbox_config" "$SANDBOX_TEST_ROOT/before"
  if "$@" >"$SANDBOX_TEST_ROOT/output" 2>"$SANDBOX_TEST_ROOT/error"; then
    fail "accepted unsafe config or arguments: $*"
  fi
  cmp -s "$sandbox_config" "$SANDBOX_TEST_ROOT/before" ||
    fail 'rejected update changed the config'
}

"$SANDBOX_TEST_TOOL" create-subscription sandbox-test >/dev/null
sandbox_config="$CODEX_HOMES_ROOT/sandbox-test/config.toml"
cp "$sandbox_config" "$SANDBOX_TEST_ROOT/original"

"$SANDBOX_TEST_TOOL" set-sandbox sandbox-test workspace-write >/dev/null
grep -Fxq 'sandbox_mode = "workspace-write"' "$sandbox_config"
grep -Fxq 'approval_policy = "on-request"' "$sandbox_config"
grep -Fxq 'approvals_reviewer = "user"' "$sandbox_config"
"$SANDBOX_TEST_TOOL" show sandbox-test >"$SANDBOX_TEST_ROOT/output"
grep -Fq 'Sandbox default: workspace-write' "$SANDBOX_TEST_ROOT/output"

# A second edit must replace the defaults, preserving identity authentication
# and nested settings even when they contain keys with the same names.
cat >>"$sandbox_config" <<'EOF'

[sandbox_workspace_write]
network_access = true
writable_roots = ["/explicit/user/choice"]

[profiles.custom]
sandbox_mode = "danger-full-access"
approval_policy = "never"
approvals_reviewer = "auto_review"

[mcp_servers.example]
command = "example"
args = ["--sandbox"]
EOF
sed -n '/^\[/,$p' "$sandbox_config" >"$SANDBOX_TEST_ROOT/tables-before"
"$SANDBOX_TEST_TOOL" set-sandbox sandbox-test read-only >/dev/null
grep -Fxq 'sandbox_mode = "read-only"' "$sandbox_config"
grep -Fxq 'cli_auth_credentials_store = "file"' "$sandbox_config"
sed -n '/^\[/,$p' "$sandbox_config" >"$SANDBOX_TEST_ROOT/tables-after"
cmp -s "$SANDBOX_TEST_ROOT/tables-before" "$SANDBOX_TEST_ROOT/tables-after" ||
  fail 'changing defaults changed nested configuration'

cp "$sandbox_config" "$SANDBOX_TEST_ROOT/before"
"$SANDBOX_TEST_TOOL" set-sandbox sandbox-test read-only >/dev/null
cmp -s "$sandbox_config" "$SANDBOX_TEST_ROOT/before" ||
  fail 'repeating a sandbox update changed the config'
if [[ "$(uname -s)" == Darwin ]]; then
  sandbox_mode="$(stat -f '%Lp' "$sandbox_config")"
else
  sandbox_mode="$(stat -c '%a' "$sandbox_config")"
fi
[[ "$sandbox_mode" == 600 ]] || fail 'sandbox update weakened private file permissions'

expect_unchanged_failure "$SANDBOX_TEST_TOOL" set-sandbox sandbox-test danger-full-access
expect_unchanged_failure "$SANDBOX_TEST_TOOL" set-sandbox sandbox-test

"$SANDBOX_TEST_TOOL" set-sandbox sandbox-test inherit >/dev/null
sed -n '1,/^\[/p' "$sandbox_config" >"$SANDBOX_TEST_ROOT/root-config"
if grep -Eq '^(sandbox_mode|approval_policy|approvals_reviewer)[[:space:]]*=' \
  "$SANDBOX_TEST_ROOT/root-config"; then
  fail 'inherit retained root sandbox defaults'
fi
sed -n '/^\[/,$p' "$sandbox_config" >"$SANDBOX_TEST_ROOT/tables-after"
cmp -s "$SANDBOX_TEST_ROOT/tables-before" "$SANDBOX_TEST_ROOT/tables-after" ||
  fail 'inherit removed nested policies'

# Native provider config must stay valid in shape when adding root settings.
"$SANDBOX_TEST_TOOL" create-api sandbox-api https://provider.example.test/v1 model-a TEST_SANDBOX_KEY >/dev/null
cp "$CODEX_HOMES_ROOT/sandbox-api/config.toml" "$SANDBOX_TEST_ROOT/api-before"
"$SANDBOX_TEST_TOOL" set-sandbox sandbox-api workspace-write >/dev/null
grep -Fxq 'model_provider = "sandbox-api"' "$CODEX_HOMES_ROOT/sandbox-api/config.toml"
grep -Fxq '[model_providers.sandbox-api]' "$CODEX_HOMES_ROOT/sandbox-api/config.toml"
python3 -I - "$SANDBOX_TEST_ROOT/api-before" "$CODEX_HOMES_ROOT/sandbox-api/config.toml" <<'PY'
import sys, tomllib
from pathlib import Path
before, after = [tomllib.loads(Path(p).read_text()) for p in sys.argv[1:]]
assert before['model_providers'] == after['model_providers']
assert 'env_key' not in after['model_providers']['sandbox-api']
PY

# Replacing existing single-line root settings must not leave duplicate keys.
cat >"$sandbox_config" <<'EOF'
sandbox_mode = 'danger-full-access'
approval_policy = "never" # previous user choice
approvals_reviewer = "auto_review"
[tui]
terminal_title = []
EOF
"$SANDBOX_TEST_TOOL" set-sandbox sandbox-test workspace-write >/dev/null
[[ "$(grep -c '^sandbox_mode[[:space:]]*=' "$sandbox_config")" == 1 ]] ||
  fail 'update left duplicate sandbox keys'
grep -Fxq 'approval_policy = "on-request"' "$sandbox_config"

# Conservative refusal is safer than a regex editor corrupting complex TOML
# or silently mixing the legacy mode with the newer permissions system.
cat >"$sandbox_config" <<'EOF'
instructions = """
[not_a_real_table]
sandbox_mode = "this is text"
"""
EOF
expect_unchanged_failure "$SANDBOX_TEST_TOOL" set-sandbox sandbox-test workspace-write
for permission_setting in 'default_permissions = ":workspace"' \
  'permissions = {}' '[permissions.custom]' 'permissions.custom.extends = ":workspace"' \
  '[sandbox_mode]' '["approval_policy"]' '[[approvals_reviewer]]'; do
  printf '%s\n' "$permission_setting" >"$sandbox_config"
  expect_unchanged_failure "$SANDBOX_TEST_TOOL" set-sandbox sandbox-test workspace-write
done

printf 'sandbox_mode = ""\n' >"$sandbox_config"
"$SANDBOX_TEST_TOOL" show sandbox-test >"$SANDBOX_TEST_ROOT/output"
grep -Fq 'Sandbox default: custom configuration; inspect config.toml' "$SANDBOX_TEST_ROOT/output" ||
  fail 'invalid empty mode was reported as an inherited default'

# Multiline arrays can contain bracket-shaped text without turning later root
# keys into table settings or leaving duplicate sandbox keys behind.
cat >"$sandbox_config" <<'EOF'
values = [
  ["nested", "[text]"],
  "# comment inside a string",
]
sandbox_mode = "danger-full-access"
[tui]
terminal_title = []
EOF
"$SANDBOX_TEST_TOOL" set-sandbox sandbox-test read-only >/dev/null
[[ "$(grep -c '^sandbox_mode[[:space:]]*=' "$sandbox_config")" == 1 ]] ||
  fail 'root array hid an existing sandbox key'
grep -Fxq '  ["nested", "[text]"],' "$sandbox_config"
grep -Fxq 'sandbox_mode = "read-only"' "$sandbox_config"

cp "$SANDBOX_TEST_ROOT/original" "$SANDBOX_TEST_ROOT/symlink-target"
mv "$sandbox_config" "$SANDBOX_TEST_ROOT/previous-config"
ln -s "$SANDBOX_TEST_ROOT/symlink-target" "$sandbox_config"
expect_unchanged_failure "$SANDBOX_TEST_TOOL" set-sandbox sandbox-test workspace-write
[[ -L "$sandbox_config" ]] || fail 'update replaced a symlinked config'

printf 'Sandbox config tests passed.\n'
