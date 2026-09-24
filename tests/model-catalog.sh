#!/usr/bin/env bash
# Offline regressions for provider-backed CLI and IDE model picker catalogs.
set -euo pipefail
CATALOG_TEST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$CATALOG_TEST_REPO/tests/common.sh"
CATALOG_TEST_TOOL="$(resolve_codex_home_tool "$CATALOG_TEST_REPO/bin")"
export CATALOG_TEST_ROOT
CATALOG_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-catalog-test.XXXXXX")"
trap 'rm -rf -- "$CATALOG_TEST_ROOT"' EXIT
export CODEX_HOMES_ROOT="$CATALOG_TEST_ROOT/identity homes"
export CODEX_UMGPT_MODELS_FILE="$CATALOG_TEST_ROOT/defaults.toml"
mkdir -p "$CATALOG_TEST_ROOT/bin"

fail() { printf 'Model catalog test failure: %s\n' "$*" >&2; exit 1; }
expect_failure() {
  if "$CATALOG_TEST_TOOL" refresh-models "$1" >"$CATALOG_TEST_ROOT/output" 2>"$CATALOG_TEST_ROOT/error"; then
    fail "accepted invalid refresh: $1"
  fi
  grep -Fq -- "$2" "$CATALOG_TEST_ROOT/error" || fail "missing diagnostic: $2"
}

cat > "$CATALOG_TEST_ROOT/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CATALOG_TEST_ROOT/curl-args"
cat > "$CATALOG_TEST_ROOT/curl-config"
if [[ "${CATALOG_TEST_HTTP_FAIL:-0}" == 1 ]]; then exit 22; fi
cat "$CATALOG_TEST_ROOT/response.json"
EOF
cat > "$CATALOG_TEST_ROOT/bin/codex" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == 'debug models --bundled' ]] || exit 95
if [[ -f "$CODEX_HOME/config.toml" && "${CATALOG_TEST_PARSE_FAIL:-0}" == 1 ]]; then
  printf 'synthetic catalog parser rejection\n' >&2
  exit 96
fi
cat "$CATALOG_TEST_ROOT/bundled.json"
EOF
chmod +x "$CATALOG_TEST_ROOT/bin/curl" "$CATALOG_TEST_ROOT/bin/codex"
export PATH="$CATALOG_TEST_ROOT/bin:$PATH"
cat > "$CATALOG_TEST_ROOT/response.json" <<'EOF'
{"data":[{"id":"claude-test"},{"id":"gpt-test"},{"id":"o3"},{"id":"claude-test"},{"id":"gemini-test"},{"id":"gpt-IMAGE-test"},{"id":"text-embedding-test"}]}
EOF
cat > "$CATALOG_TEST_ROOT/bundled.json" <<'EOF'
{"models":[{"slug":"gpt-test","description":"Known coding model","base_instructions":"Keep these instructions","supported_reasoning_levels":[{"effort":"medium","description":"Medium"}],"context_window":123456,"upgrade":{"model":"unadvertised-model"}},{"slug":"unadvertised-model"}]}
EOF
"$CATALOG_TEST_TOOL" create-umgpt gpt-test >/dev/null
"$CATALOG_TEST_TOOL" create-umgpt-low claude-test >/dev/null
for name in umgpt umgpt-low; do
  printf 'UMGPT_API_KEY=synthetic-catalog-key\n' > "$CODEX_HOMES_ROOT/$name/.env"
  printf '\n[projects."/example"]\ntrust_level = "trusted"\n' >> "$CODEX_HOMES_ROOT/$name/config.toml"
  "$CATALOG_TEST_TOOL" refresh-models "$name" > "$CATALOG_TEST_ROOT/output"
  "$CATALOG_TEST_TOOL" show "$name" >/dev/null
done
catalog="$CODEX_HOMES_ROOT/umgpt-low/model-catalog.json"
jq -e '[.models[].slug] == ["claude-test", "gemini-test", "gpt-test", "o3"]' "$catalog" >/dev/null ||
  fail 'low-sensitivity catalog lost models, deduplication, or selected-model ordering'
jq -e '[.models[].slug] == ["gpt-test", "o3"]' "$CODEX_HOMES_ROOT/umgpt/model-catalog.json" >/dev/null ||
  fail 'normal catalog did not preserve the OpenAI text scope'
jq -e '.models[] | select(.slug == "gpt-test") | .context_window == 123456 and .base_instructions == "Keep these instructions" and .upgrade == null' "$catalog" >/dev/null ||
  fail 'known model metadata changed or an unadvertised upgrade survived'
jq -e '.models[] | select(.slug == "claude-test") | .visibility == "list" and .supported_in_api and .input_modalities == ["text"] and .supported_reasoning_levels == [] and .context_window == null' "$catalog" >/dev/null ||
  fail 'unknown model invented capabilities or was hidden from the picker'
if grep -Fq 'synthetic-catalog-key' "$catalog" "$CATALOG_TEST_ROOT/output" "$CATALOG_TEST_ROOT/curl-args"; then
  fail 'refresh exposed credentials'
fi
grep -Fq 'Authorization: Bearer synthetic-catalog-key' "$CATALOG_TEST_ROOT/curl-config" || fail 'refresh omitted provider authentication'
grep -Fq 'trust_level = "trusted"' "$CODEX_HOMES_ROOT/umgpt-low/config.toml" || fail 'refresh lost unrelated settings'

cp "$CODEX_HOMES_ROOT/umgpt-low/config.toml" "$CATALOG_TEST_ROOT/config-before"
cp "$catalog" "$CATALOG_TEST_ROOT/catalog-before"
"$CATALOG_TEST_TOOL" refresh-models umgpt-low >/dev/null
cmp -s "$CATALOG_TEST_ROOT/config-before" "$CODEX_HOMES_ROOT/umgpt-low/config.toml" || fail 'refresh duplicated or moved configuration'
CATALOG_TEST_HTTP_FAIL=1 expect_failure umgpt-low 'model request failed'
CATALOG_TEST_PARSE_FAIL=1 expect_failure umgpt-low 'Codex rejected'
printf '%s\n' '{"data":[{"id":"bad model"}]}' > "$CATALOG_TEST_ROOT/response.json"
expect_failure umgpt-low 'invalid model ID'
printf '%s\n' '{"data":[{"id":"gpt-image-test"}]}' > "$CATALOG_TEST_ROOT/response.json"
expect_failure umgpt-low 'no models allowed'
cmp -s "$CATALOG_TEST_ROOT/config-before" "$CODEX_HOMES_ROOT/umgpt-low/config.toml" || fail 'failed refresh changed configuration'
cmp -s "$CATALOG_TEST_ROOT/catalog-before" "$catalog" || fail 'failed refresh replaced the catalog'

# A scope change must not leave a broader catalog usable by the normal identity.
cp "$catalog" "$CODEX_HOMES_ROOT/umgpt/model-catalog.json"
source "$CATALOG_TEST_TOOL"
if (validate_umgpt_identity_config umgpt) >/dev/null 2>&1; then
  fail 'normal identity accepted another vendor in its catalog'
fi
printf '%s\n' '{"data":[{"id":"gpt-test"}]}' > "$CATALOG_TEST_ROOT/response.json"
"$CATALOG_TEST_TOOL" refresh-models umgpt >/dev/null
validate_umgpt_identity_config umgpt
printf '%s\n' '{"models":[42]}' > "$CODEX_HOMES_ROOT/umgpt/model-catalog.json"
if (validate_umgpt_identity_config umgpt) >/dev/null 2>&1; then
  fail 'normal identity accepted a malformed catalog entry'
fi
printf '%s\n' '{"models":[{"slug":"gpt-test\ngpt-other"}]}' > "$CODEX_HOMES_ROOT/umgpt/model-catalog.json"
if (validate_umgpt_identity_config umgpt) >/dev/null 2>&1; then
  fail 'normal identity accepted a multiline model ID'
fi
printf 'model_catalog_json = "/custom/catalog.json"\n' > "$CATALOG_TEST_ROOT/custom-setting"
cat "$CATALOG_TEST_ROOT/custom-setting" "$CATALOG_TEST_ROOT/config-before" > "$CODEX_HOMES_ROOT/umgpt-low/config.toml"
expect_failure umgpt-low 'uses another model_catalog_json'
"$CATALOG_TEST_TOOL" create-subscription subscription >/dev/null
expect_failure subscription 'requires a scoped U-M GPT identity'

printf 'Model catalog tests passed.\n'
