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
jq -e '[.models[].slug] == ["claude-test", "gpt-test", "o3", "gemini-test"]' "$catalog" >/dev/null ||
  fail 'low-sensitivity catalog lost models, deduplication, or family ordering'
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
printf '%s\n' '{"data":[{"id":"gpt-test"},{"id":"claude-other"}]}' > "$CATALOG_TEST_ROOT/response.json"
expect_failure umgpt-low "configured model 'claude-test' is not advertised"
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

# Scrambled versions cover double-digit components, Claude naming styles,
# GPT variants, parameter counts, unknown families, and duplicate IDs.
# Pin an older configured default so Codex does not recommend the newest model
# merely because it sorts first. Keep all remaining entries in version order.
cat > "$CATALOG_TEST_ROOT/response.json" <<'EOF'
{"data":[
  {"id":"o1"}, {"id":"gemini-3.9-flash"}, {"id":"gpt-5.9"},
  {"id":"claude-opus-4-9"}, {"id":"gpt-4o-mini"}, {"id":"gpt-5.10-mini"},
  {"id":"Llama-3.3-70B-Instruct"}, {"id":"gpt-4.1"}, {"id":"o3"},
  {"id":"claude-sonnet-5"}, {"id":"gpt-6-sol"}, {"id":"gemini-3.10-flash"},
  {"id":"claude-opus-4-10"}, {"id":"gpt-4o"}, {"id":"gpt-5.10"},
  {"id":"claude-opus-5-5"}, {"id":"claude-3-5-sonnet"}, {"id":"o3-mini"},
  {"id":"Llama-4-Scout-17B-16E-Instruct"}, {"id":"deepseek-v4-flash-0731"},
  {"id":"kimi-k3"}, {"id":"gpt-5.10"}, {"id":"gpt-4.1-mini"},
  {"id":"newvendor-2"}, {"id":"newvendor-10"}, {"id":"newvendor-test"},
  {"id":"gpt-image-2"}, {"id":"text-embedding-3-large"}
]}
EOF
cat > "$CATALOG_TEST_ROOT/expected-low" <<'EOF'
claude-opus-5-5
claude-sonnet-5
claude-opus-4-10
claude-opus-4-9
claude-3-5-sonnet
gpt-6-sol
gpt-5.10
gpt-5.10-mini
gpt-5.9
gpt-4.1
gpt-4.1-mini
gpt-4o
gpt-4o-mini
o3
o3-mini
o1
gemini-3.10-flash
gemini-3.9-flash
deepseek-v4-flash-0731
kimi-k3
Llama-4-Scout-17B-16E-Instruct
Llama-3.3-70B-Instruct
newvendor-10
newvendor-2
newvendor-test
EOF
grep -E '^(gpt-|o[0-9])' "$CATALOG_TEST_ROOT/expected-low" > "$CATALOG_TEST_ROOT/expected-openai"
for scope in openai low; do
  name="ordered-$scope"
  if [[ "$scope" == openai ]]; then
    "$CATALOG_TEST_TOOL" create-umgpt gpt-4o "$name" >/dev/null
    default_model=gpt-4o
  else
    "$CATALOG_TEST_TOOL" create-umgpt-low claude-3-5-sonnet "$name" >/dev/null
    default_model=claude-3-5-sonnet
  fi
  printf 'UMGPT_API_KEY=synthetic-catalog-key\n' > "$CODEX_HOMES_ROOT/$name/.env"
  "$CATALOG_TEST_TOOL" refresh-models "$name" >/dev/null
  ordered_catalog="$CODEX_HOMES_ROOT/$name/model-catalog.json"
  {
    printf '%s\n' "$default_model"
    grep -Fxv -- "$default_model" "$CATALOG_TEST_ROOT/expected-$scope"
  } > "$CATALOG_TEST_ROOT/expected-picker"
  jq -r '.models[].slug' "$ordered_catalog" > "$CATALOG_TEST_ROOT/actual"
  cmp -s "$CATALOG_TEST_ROOT/expected-picker" "$CATALOG_TEST_ROOT/actual" ||
    fail "$scope picker did not pin the default then sort versions within families"
  jq -e --arg selected "$default_model" '.models | min_by(.priority) | .slug == $selected' "$ordered_catalog" >/dev/null ||
    fail "$scope picker would recommend a model other than the configured default"
  jq -e '[.models[].priority] == [range(0; .models | length)]' "$ordered_catalog" >/dev/null ||
    fail "$scope picker priorities disagree with display order"
  grep -Fxq "model = \"$default_model\"" "$CODEX_HOMES_ROOT/$name/config.toml" ||
    fail "$scope ordering changed the saved default"
  "$CATALOG_TEST_TOOL" models "$name" | sed -n 's/^  //p' > "$CATALOG_TEST_ROOT/actual"
  cmp -s "$CATALOG_TEST_ROOT/expected-$scope" "$CATALOG_TEST_ROOT/actual" ||
    fail "$scope printed list did not retain family/version order"
done

# A single editable settings file controls both defaults and preferred order.
export CODEX_HOMES_ROOT="$CATALOG_TEST_ROOT/preferences"
export CODEX_UMGPT_MODELS_FILE="$CATALOG_TEST_ROOT/preferences.toml"
"$CATALOG_TEST_TOOL" create-umgpt gpt-4o >/dev/null
"$CATALOG_TEST_TOOL" create-umgpt-low claude-3-5-sonnet >/dev/null
cat > "$CODEX_UMGPT_MODELS_FILE" <<'EOF'
umgpt = "gpt-4o"
umgpt_low = "claude-3-5-sonnet"
umgpt_order = ["o3", "gpt-5.9", "gpt-4o", "o3", "gpt-unavailable"]
umgpt_low_order = ["gemini-3.10-flash", "claude-sonnet-5", "gpt-6-sol"]
EOF
for name in umgpt umgpt-low; do
  printf 'UMGPT_API_KEY=synthetic-catalog-key\n' > "$CODEX_HOMES_ROOT/$name/.env"
  "$CATALOG_TEST_TOOL" refresh-models "$name" >/dev/null
done
jq -e '[.models[:3][].slug] == ["gpt-4o","o3","gpt-5.9"] and
  ([.models[].slug] | index("gpt-unavailable") == null) and
  ([.models[].slug] | length == (unique | length))' "$CODEX_HOMES_ROOT/umgpt/model-catalog.json" >/dev/null ||
  fail 'preferred order lost the default, repeated entries, or injected an unavailable model'
jq -e '[.models[:4][].slug] == ["claude-3-5-sonnet","gemini-3.10-flash","claude-sonnet-5","gpt-6-sol"]' "$CODEX_HOMES_ROOT/umgpt-low/model-catalog.json" >/dev/null ||
  fail 'preferred order could not cross model families'
"$CATALOG_TEST_TOOL" model-settings > "$CATALOG_TEST_ROOT/settings-output"
grep -Fq "Edit your settings: $CODEX_UMGPT_MODELS_FILE" "$CATALOG_TEST_ROOT/settings-output" ||
  fail 'settings command hid the editable file'
grep -Fq 'umgpt_low_order = ["gemini-3.10-flash","claude-sonnet-5","gpt-6-sol"]' "$CATALOG_TEST_ROOT/settings-output" ||
  fail 'settings command hid preferred model order'

# Applying edits and changing defaults must update an existing picker offline.
jq '[.models[] | del(.priority)] | sort_by(.slug)' "$CODEX_HOMES_ROOT/umgpt/model-catalog.json" > "$CATALOG_TEST_ROOT/metadata-before"
sed 's/umgpt = "gpt-4o"/umgpt = "gpt-5.9"/' "$CODEX_UMGPT_MODELS_FILE" > "$CATALOG_TEST_ROOT/edited-settings"
cp "$CATALOG_TEST_ROOT/edited-settings" "$CODEX_UMGPT_MODELS_FILE"
CATALOG_TEST_HTTP_FAIL=1 "$CATALOG_TEST_TOOL" apply-model-settings >/dev/null
jq -e '[.models[:3][].slug] == ["gpt-5.9","o3","gpt-4o"]' "$CODEX_HOMES_ROOT/umgpt/model-catalog.json" >/dev/null ||
  fail 'apply-model-settings did not update the picker default and preferred order'
grep -Fxq 'model = "gpt-5.9"' "$CODEX_HOMES_ROOT/umgpt/config.toml" ||
  fail 'apply-model-settings did not update the active default'
CATALOG_TEST_HTTP_FAIL=1 "$CATALOG_TEST_TOOL" set-umgpt-default umgpt gpt-4o >/dev/null
jq -e '[.models[:3][].slug] == ["gpt-4o","o3","gpt-5.9"]' "$CODEX_HOMES_ROOT/umgpt/model-catalog.json" >/dev/null ||
  fail 'changing a default lost preferred order or left the old picker default'
grep -Fq 'umgpt_order = ["o3","gpt-5.9","gpt-4o","o3","gpt-unavailable"]' "$CODEX_UMGPT_MODELS_FILE" ||
  fail 'changing a default overwrote saved order preferences'
jq '[.models[] | del(.priority)] | sort_by(.slug)' "$CODEX_HOMES_ROOT/umgpt/model-catalog.json" > "$CATALOG_TEST_ROOT/metadata-after"
cmp -s "$CATALOG_TEST_ROOT/metadata-before" "$CATALOG_TEST_ROOT/metadata-after" ||
  fail 'reordering changed model capabilities'

# Invalid settings must fail before changing either active config or catalog.
cp "$CODEX_UMGPT_MODELS_FILE" "$CATALOG_TEST_ROOT/valid-settings"
cp "$CODEX_HOMES_ROOT/umgpt/model-catalog.json" "$CATALOG_TEST_ROOT/picker-before"
cp "$CODEX_HOMES_ROOT/umgpt/config.toml" "$CATALOG_TEST_ROOT/active-before"
for bad_order in '["claude-sonnet-5"]' '["gpt-image-2"]' '[""]' '[42]' '["gpt-4o\\ngpt-5.9"]'; do
  printf 'umgpt = "gpt-4o"\numgpt_low = "claude-3-5-sonnet"\numgpt_order = %s\n' "$bad_order" > "$CODEX_UMGPT_MODELS_FILE"
  if "$CATALOG_TEST_TOOL" apply-model-settings >/dev/null 2>&1; then
    fail "accepted invalid preferred order: $bad_order"
  fi
  cmp -s "$CATALOG_TEST_ROOT/picker-before" "$CODEX_HOMES_ROOT/umgpt/model-catalog.json" ||
    fail 'invalid settings changed the picker'
  cmp -s "$CATALOG_TEST_ROOT/active-before" "$CODEX_HOMES_ROOT/umgpt/config.toml" ||
    fail 'invalid settings changed the active default'
done
cp "$CATALOG_TEST_ROOT/valid-settings" "$CODEX_UMGPT_MODELS_FILE"
printf 'umgpt_order = []\n' >> "$CODEX_UMGPT_MODELS_FILE"
if "$CATALOG_TEST_TOOL" apply-model-settings >/dev/null 2>&1; then
  fail 'accepted duplicate model-order keys'
fi
cp "$CATALOG_TEST_ROOT/valid-settings" "$CODEX_UMGPT_MODELS_FILE"
# Clear both preferred lists while retaining explicit defaults.
sed 's/^umgpt_order = .*/umgpt_order = []/; s/^umgpt_low_order = .*/umgpt_low_order = []/' "$CODEX_UMGPT_MODELS_FILE" > "$CATALOG_TEST_ROOT/edited-settings"
cp "$CATALOG_TEST_ROOT/edited-settings" "$CODEX_UMGPT_MODELS_FILE"
CATALOG_TEST_HTTP_FAIL=1 "$CATALOG_TEST_TOOL" apply-model-settings >/dev/null
jq -e '[.models[:3][].slug] == ["gpt-4o","gpt-6-sol","gpt-5.10"]' "$CODEX_HOMES_ROOT/umgpt/model-catalog.json" >/dev/null ||
  fail 'clearing preferred order did not restore automatic sorting'

printf 'Model catalog tests passed.\n'
