#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$ROOT/tests/common.sh"

fail() {
  printf 'test failure: %s\n' "$*" >&2
  exit 1
}

require_command() {
  local command="$1"
  local guidance="$2"
  command -v "$command" >/dev/null 2>&1 ||
    fail "required command '$command' was not found. $guidance"
}

quiet_test_command() {
  if "$@" 2> "$TEST_ROOT/test-command-error"; then
    return 0
  fi
  cat "$TEST_ROOT/test-command-error" >&2
  fail "test command failed: $1"
}

assert_line_once() {
  local file="$1"
  local expected="$2"
  local count
  count="$(grep -Fxc -- "$expected" "$file" || true)"
  [[ "$count" -eq 1 ]] ||
    fail "expected exactly one line '$expected' in $file; found $count"
}

assert_subscription_config() {
  local file="$1"
  assert_line_once "$file" 'cli_auth_credentials_store = "file"'
  assert_line_once "$file" '[tui]'
  assert_line_once "$file" 'status_line = ["model-with-reasoning", "context-remaining", "current-dir"]'
  assert_line_once "$file" 'terminal_title = ["app-name", "project", "model"]'
}

assert_api_config() {
  local file="$1"
  local name="$2"
  local model="$3"
  local base_url="$4"
  local key_env="$5"
  local api_version="${6:-}"

  assert_line_once "$file" "model = \"$model\""
  assert_line_once "$file" "model_provider = \"$name\""
  assert_line_once "$file" "[model_providers.$name]"
  assert_line_once "$file" "base_url = \"$base_url\""
  assert_line_once "$file" "env_key = \"$key_env\""
  assert_line_once "$file" 'wire_api = "responses"'
  assert_line_once "$file" '[tui]'
  assert_line_once "$file" 'status_line = ["model-with-reasoning", "context-remaining", "current-dir"]'
  assert_line_once "$file" 'terminal_title = ["app-name", "project", "model"]'
  if [[ -n "$api_version" ]]; then
    assert_line_once "$file" "query_params = { api-version = \"$api_version\" }"
  elif grep -q '^query_params[[:space:]]*=' "$file"; then
    fail "unexpected query_params in $file"
  fi
}

if (( BASH_VERSINFO[0] < 3 )); then
  fail "Bash 3.2 or newer is required; found $BASH_VERSION"
fi
require_command direnv "Install direnv and its shell hook; see INSTALLATION.md."
require_command jq "Install jq; see INSTALLATION.md."
require_command expect "Install expect to run the interactive credential tests."

LIVE_CODEX=""
if [[ "${CODEX_CONTEXTS_LIVE_TESTS:-0}" == "1" ]]; then
  require_command codex "Install the Codex CLI before enabling live doctor checks."
  LIVE_CODEX="$(command -v codex)"
fi

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-home-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export DIRENV_CONFIG="$TEST_ROOT/direnv-config"
export DIRENV_LOG_FORMAT="direnv: %s"
export XDG_DATA_HOME="$TEST_ROOT/xdg-data"
export CODEX_HOMES_ROOT="$TEST_ROOT/codex-homes"
export CODEX_MACOS_SKIP_REGISTER=1
# Keep caller overrides from selecting real settings, skills, or an editor.
unset CODEX_UMGPT_MODELS_FILE CODEX_SKILLS_SOURCE CODEX_VSCODE_CLI \
  CODEX_VSCODE_EXTENSIONS_DIR CODEX_VSCODE_DOCK_LABEL
# Do not let the caller's direnv state restore its PATH over our mock commands.
unset DIRENV_DIFF DIRENV_DIR DIRENV_FILE DIRENV_WATCHES
mkdir -p "$HOME" "$DIRENV_CONFIG" "$TEST_ROOT/project" "$TEST_ROOT/offline-bin"
git -C "$TEST_ROOT/project" init -q

# Make accidental calls to the two network-capable programs used by this
# project fail. Individual provider tests place an explicit curl double first.
for blocked_command in codex curl; do
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "unexpected live command in offline tests: %s\\n" "$(basename "$0")" >&2' \
    'exit 97' \
    > "$TEST_ROOT/offline-bin/$blocked_command"
  chmod +x "$TEST_ROOT/offline-bin/$blocked_command"
done
export PATH="$TEST_ROOT/offline-bin:$PATH"

if [[ "${CODEX_CONTEXTS_LIVE_TESTS:-0}" == "1" ]]; then
  printf 'Running tests with temporary identities; opt-in checks may contact services.\n'
else
  printf 'Running offline tests with temporary identities and mock commands.\n'
fi

TOOL="$(resolve_codex_home_tool "$ROOT/bin")"
RENAMED_TOOL_DIR="$TEST_ROOT/renamed-bin"
mkdir -p "$RENAMED_TOOL_DIR"
ln -s "$TOOL" "$RENAMED_TOOL_DIR/code-home"
[[ "$(resolve_codex_home_tool "$RENAMED_TOOL_DIR")" == "$RENAMED_TOOL_DIR/code-home" ]] ||
  fail "test tool resolver did not follow an executable rename"

default_current="$(env -u CODEX_HOME -u CODEX_IDENTITY "$TOOL" current)"
grep -q 'Codex identity : DEFAULT (~/.codex)' <<< "$default_current"

"$TOOL" create-subscription pro >/dev/null
[[ -f "$CODEX_HOMES_ROOT/pro/config.toml" ]]
[[ "$(cat "$CODEX_HOMES_ROOT/pro/.identity-kind")" == "chatgpt-subscription" ]]
assert_subscription_config "$CODEX_HOMES_ROOT/pro/config.toml"

"$TOOL" create-subscription business >/dev/null
[[ -f "$CODEX_HOMES_ROOT/business/config.toml" ]]
[[ "$(cat "$CODEX_HOMES_ROOT/business/.identity-kind")" == "chatgpt-subscription" ]]
assert_subscription_config "$CODEX_HOMES_ROOT/business/config.toml"

identities="$("$TOOL" list)"
grep -q '^default .*codex-default' <<< "$identities"
grep -q '^pro .*chatgpt-subscription' <<< "$identities"
grep -q '^business .*chatgpt-subscription' <<< "$identities"

identity_names="$("$TOOL" list --names)"
[[ "$identity_names" == $'business\npro' ]] ||
  fail "list --names did not return only usable identity names"
if "$TOOL" list --unknown >/dev/null 2>&1; then
  fail "expected list to reject an unknown option"
fi

mkdir -p "$TEST_ROOT/shared-skills/.system" "$TEST_ROOT/shared-skills/skill-one"
printf '%s\n' '# Skill one' > "$TEST_ROOT/shared-skills/skill-one/SKILL.md"
"$TOOL" share-skills pro "$TEST_ROOT/shared-skills" >/dev/null
[[ -L "$CODEX_HOMES_ROOT/pro/skills/skill-one" ]]
shared_skills_abs="$(cd "$TEST_ROOT/shared-skills" && pwd -P)"
[[ "$(readlink "$CODEX_HOMES_ROOT/pro/skills/skill-one")" == "$shared_skills_abs/skill-one" ]]
[[ ! -e "$CODEX_HOMES_ROOT/pro/skills/.system" ]]

mkdir -p "$CODEX_HOMES_ROOT/business/skills/skill-one"
skills_conflict="$("$TOOL" share-skills business "$TEST_ROOT/shared-skills" 2>&1)"
grep -q 'conflicts skipped' <<< "$skills_conflict"
[[ ! -L "$CODEX_HOMES_ROOT/business/skills/skill-one" ]]

"$TOOL" create-api lab-api https://api.example.test/v1 example-model LAB_API_KEY >/dev/null
[[ "$(cat "$CODEX_HOMES_ROOT/lab-api/.identity-kind")" == "api-key" ]]
assert_api_config \
  "$CODEX_HOMES_ROOT/lab-api/config.toml" \
  lab-api example-model https://api.example.test/v1 LAB_API_KEY

"$TOOL" create-azure azure-lab \
  https://azure.example.test/openai \
  deployment-name \
  AZURE_LAB_API_KEY \
  2025-04-01-preview >/dev/null
assert_api_config \
  "$CODEX_HOMES_ROOT/azure-lab/config.toml" \
  azure-lab deployment-name https://azure.example.test/openai AZURE_LAB_API_KEY \
  2025-04-01-preview

seeded_homes="$TEST_ROOT/seeded-homes"
CODEX_HOMES_ROOT="$seeded_homes" \
  "$TOOL" create-api umgpt \
    https://api.toolkit.umgpt.umich.edu/v1 gpt-5.6-terra UMGPT_API_KEY >/dev/null
CODEX_HOMES_ROOT="$seeded_homes" \
  "$TOOL" create-api umgpt-low \
    https://api.toolkit.umgpt.umich.edu/v1 claude-opus-5 UMGPT_API_KEY >/dev/null
CODEX_HOMES_ROOT="$seeded_homes" "$TOOL" umgpt-defaults >/dev/null
assert_line_once "$seeded_homes/umgpt-models.toml" 'umgpt = "gpt-5.6-terra"'
assert_line_once "$seeded_homes/umgpt-models.toml" 'umgpt_low = "claude-opus-5"'

explicit_homes="$TEST_ROOT/explicit-homes"
CODEX_HOMES_ROOT="$explicit_homes" \
  "$TOOL" create-umgpt gpt-6-luna >/dev/null
CODEX_HOMES_ROOT="$explicit_homes" \
  "$TOOL" create-umgpt-low claude-opus-5-5 >/dev/null
assert_line_once "$explicit_homes/umgpt-models.toml" 'umgpt = "gpt-6-luna"'
assert_line_once "$explicit_homes/umgpt-models.toml" 'umgpt_low = "claude-opus-5-5"'

# Test the checked-in recommendations, allowing maintainers to change them.
repository_openai_model="$(sed -n 's/^umgpt = "\([^"]*\)"$/\1/p' "$ROOT/config/umgpt-models.toml")"
repository_low_model="$(sed -n 's/^umgpt_low = "\([^"]*\)"$/\1/p' "$ROOT/config/umgpt-models.toml")"
umgpt_defaults="$("$TOOL" umgpt-defaults)"
grep -Fq "Repository defaults: $ROOT/config/umgpt-models.toml" \
  <<< "$umgpt_defaults"
grep -Fq "Local defaults: $CODEX_HOMES_ROOT/umgpt-models.toml" \
  <<< "$umgpt_defaults"
grep -Fq "  umgpt     $repository_openai_model  (U-M Azure OpenAI text only)" <<< "$umgpt_defaults"
grep -Fq "  umgpt-low $repository_low_model  (LOW-SENSITIVITY DATA ONLY)" \
  <<< "$umgpt_defaults"
assert_line_once "$CODEX_HOMES_ROOT/umgpt-models.toml" "umgpt = \"$repository_openai_model\""
assert_line_once \
  "$CODEX_HOMES_ROOT/umgpt-models.toml" \
  "umgpt_low = \"$repository_low_model\""

"$TOOL" create-umgpt >/dev/null
[[ "$(cat "$CODEX_HOMES_ROOT/umgpt/.identity-kind")" == "umgpt-openai" ]]
assert_api_config \
  "$CODEX_HOMES_ROOT/umgpt/config.toml" \
  umgpt "$repository_openai_model" https://api.toolkit.umgpt.umich.edu/v1 UMGPT_API_KEY

if "$TOOL" create-umgpt claude-sonnet-5 umgpt-claude >/dev/null 2>&1; then
  fail "create-umgpt accepted a non-OpenAI model"
fi
[[ ! -e "$CODEX_HOMES_ROOT/umgpt-claude" ]] ||
  fail "rejected U-M GPT identity left a partial directory"
if "$TOOL" create-umgpt gpt-image-2 umgpt-image >/dev/null 2>&1; then
  fail "create-umgpt accepted an image-generation model"
fi

"$TOOL" create-umgpt-low >/dev/null
[[ "$(cat "$CODEX_HOMES_ROOT/umgpt-low/.identity-kind")" == "umgpt-low" ]]
assert_api_config \
  "$CODEX_HOMES_ROOT/umgpt-low/config.toml" \
  umgpt-low "$repository_low_model" https://api.toolkit.umgpt.umich.edu/v1 UMGPT_API_KEY
if "$TOOL" create-umgpt-low text-embedding-3-large umgpt-embedding >/dev/null 2>&1; then
  fail "create-umgpt-low accepted an embedding model"
fi

umgpt_status="$("$TOOL" show umgpt)"
grep -Fq 'Model scope     : U-M Azure OpenAI text models only' <<< "$umgpt_status"
umgpt_low_status="$("$TOOL" show umgpt-low)"
grep -Fq 'Model scope     : broader U-M text models; LOW-SENSITIVITY DATA ONLY' \
  <<< "$umgpt_low_status"

"$TOOL" set-umgpt-default umgpt gpt-settings-test >/dev/null
"$TOOL" set-umgpt-default umgpt-low claude-opus-5-5 >/dev/null
assert_line_once "$CODEX_HOMES_ROOT/umgpt-models.toml" 'umgpt = "gpt-settings-test"'
assert_line_once \
  "$CODEX_HOMES_ROOT/umgpt-models.toml" \
  'umgpt_low = "claude-opus-5-5"'
assert_line_once "$CODEX_HOMES_ROOT/umgpt/config.toml" 'model = "gpt-settings-test"'
assert_line_once "$CODEX_HOMES_ROOT/umgpt-low/config.toml" 'model = "claude-opus-5-5"'

"$TOOL" reset-umgpt-defaults >/dev/null
assert_line_once "$CODEX_HOMES_ROOT/umgpt-models.toml" "umgpt = \"$repository_openai_model\""
assert_line_once \
  "$CODEX_HOMES_ROOT/umgpt-models.toml" \
  "umgpt_low = \"$repository_low_model\""
assert_line_once "$CODEX_HOMES_ROOT/umgpt/config.toml" "model = \"$repository_openai_model\""
assert_line_once "$CODEX_HOMES_ROOT/umgpt-low/config.toml" "model = \"$repository_low_model\""

# Manual edits are supported: validate and apply both values in one command.
printf 'umgpt = "gpt-settings-test"\numgpt_low = "claude-opus-5-5"\n' \
  > "$TEST_ROOT/umgpt-models-edited.toml"
mv "$TEST_ROOT/umgpt-models-edited.toml" "$CODEX_HOMES_ROOT/umgpt-models.toml"
"$TOOL" apply-umgpt-defaults >/dev/null
assert_line_once "$CODEX_HOMES_ROOT/umgpt/config.toml" 'model = "gpt-settings-test"'
assert_line_once "$CODEX_HOMES_ROOT/umgpt-low/config.toml" 'model = "claude-opus-5-5"'

models_before_invalid="$(cat "$CODEX_HOMES_ROOT/umgpt-models.toml")"
printf '%s\n' \
  "umgpt = \"$repository_openai_model\"" \
  'umgpt = "gpt-duplicate-test"' \
  "umgpt_low = \"$repository_low_model\"" \
  > "$CODEX_HOMES_ROOT/umgpt-models.toml"
if "$TOOL" apply-umgpt-defaults >/dev/null 2>&1; then
  fail "apply-umgpt-defaults accepted duplicate model keys"
fi
printf '%s\n' "$models_before_invalid" > "$CODEX_HOMES_ROOT/umgpt-models.toml"

models_before_invalid="$(cat "$CODEX_HOMES_ROOT/umgpt-models.toml")"
if "$TOOL" set-umgpt-default umgpt claude-sonnet-5 >/dev/null 2>&1; then
  fail "set-umgpt-default accepted a non-OpenAI model for umgpt"
fi
[[ "$(cat "$CODEX_HOMES_ROOT/umgpt-models.toml")" == "$models_before_invalid" ]] ||
  fail "a rejected U-M GPT default changed the models file"
"$TOOL" reset-umgpt-defaults >/dev/null

"$TOOL" create-api umgpt-legacy \
  https://api.toolkit.umgpt.umich.edu/v1 gpt-5 UMGPT_API_KEY >/dev/null
legacy_status="$("$TOOL" show umgpt-legacy)"
grep -Fq 'Model scope     : UNSET; run set-umgpt-scope before launching Codex' \
  <<< "$legacy_status"
"$TOOL" set-umgpt-scope umgpt-legacy openai-only >/dev/null
[[ "$(cat "$CODEX_HOMES_ROOT/umgpt-legacy/.identity-kind")" == "umgpt-openai" ]]

"$TOOL" create-api umgpt-legacy-claude \
  https://api.toolkit.umgpt.umich.edu/v1 claude-opus-5 UMGPT_API_KEY >/dev/null
if "$TOOL" set-umgpt-scope umgpt-legacy-claude openai-only >/dev/null 2>&1; then
  fail "set-umgpt-scope marked a Claude identity OpenAI-only"
fi
"$TOOL" set-umgpt-scope umgpt-legacy-claude low-sensitivity >/dev/null
[[ "$(cat "$CODEX_HOMES_ROOT/umgpt-legacy-claude/.identity-kind")" == "umgpt-low" ]]

mkdir -p "$TEST_ROOT/shared-skills/skill-two"
printf '%s\n' '# Skill two' > "$TEST_ROOT/shared-skills/skill-two/SKILL.md"
"$TOOL" share-skills-all "$TEST_ROOT/shared-skills" >/dev/null 2>&1
[[ -L "$CODEX_HOMES_ROOT/lab-api/skills/skill-two" ]]
[[ -L "$CODEX_HOMES_ROOT/azure-lab/skills/skill-two" ]]
[[ -L "$CODEX_HOMES_ROOT/umgpt/skills/skill-two" ]]
[[ -L "$CODEX_HOMES_ROOT/umgpt-low/skills/skill-two" ]]

for reserved_provider in openai ollama lmstudio amazon-bedrock; do
  if "$TOOL" create-api \
    "$reserved_provider" https://api.example.test/v1 model KEY >/dev/null 2>&1
  then
    fail "expected reserved provider ID '$reserved_provider' to be rejected"
  fi
  [[ ! -e "$CODEX_HOMES_ROOT/$reserved_provider" ]] ||
    fail "reserved provider rejection left a partial identity: $reserved_provider"
done

special_secret='space \\ " $ ` ! end'
CODEX_TEST_TOOL="$TOOL" \
CODEX_TEST_HOME="$HOME" \
CODEX_TEST_HOMES_ROOT="$CODEX_HOMES_ROOT" \
CODEX_TEST_PATH="$PATH" \
CODEX_TEST_SECRET="$special_secret" \
expect -c '
  set timeout 10
  spawn env -i \
    HOME=$env(CODEX_TEST_HOME) \
    CODEX_HOMES_ROOT=$env(CODEX_TEST_HOMES_ROOT) \
    PATH=$env(CODEX_TEST_PATH) \
    $env(CODEX_TEST_TOOL) set-key lab-api
  expect {
    -exact "Enter LAB_API_KEY for lab-api: " {}
    timeout { exit 124 }
    eof { exit 125 }
  }
  send -- "$env(CODEX_TEST_SECRET)\r"
  expect eof
  set child_status [wait]
  exit [lindex $child_status 3]
' > "$TEST_ROOT/set-key-output"

if grep -Fq -- "$special_secret" "$TEST_ROOT/set-key-output"; then
  fail "set-key echoed the entered secret"
fi
if [[ "$(uname -s)" == "Darwin" ]]; then
  key_mode="$(stat -f '%Lp' "$CODEX_HOMES_ROOT/lab-api/.env")"
else
  key_mode="$(stat -c '%a' "$CODEX_HOMES_ROOT/lab-api/.env")"
fi
[[ "$key_mode" == "600" ]] || fail "set-key wrote .env with mode $key_mode, not 600"
loaded_secret="$(
  env -u LAB_API_KEY /bin/bash -c '
    set -eu
    source "$1"
    printf "%s" "$LAB_API_KEY"
  ' _ "$CODEX_HOMES_ROOT/lab-api/.env"
)"
[[ "$loaded_secret" == "$special_secret" ]] || fail "set-key did not preserve shell metacharacters"

printf 'LAB_API_KEY=test-secret\n' > "$CODEX_HOMES_ROOT/lab-api/.env"
chmod 600 "$CODEX_HOMES_ROOT/lab-api/.env"

stored_status="$("$TOOL" show lab-api)"
grep -q 'API key env    : LAB_API_KEY (stored; enter its project or use codex-home run)' \
  <<< "$stored_status"

mkdir -p "$TEST_ROOT/fake-curl-bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$@" > "$CODEX_TEST_CURL_ARGS"' \
  'cat > "$CODEX_TEST_CURL_CONFIG"' \
  'printf "%s\n" "{\"data\":[{\"id\":\"model-a\"},{\"id\":\"model-b\"},{\"id\":\"gpt-6-sol\"},{\"id\":\"o3\"},{\"id\":\"claude-sonnet-5\"},{\"id\":\"gpt-image-2\"},{\"id\":\"text-embedding-3-large\"}]}"' \
  > "$TEST_ROOT/fake-curl-bin/curl"
chmod +x "$TEST_ROOT/fake-curl-bin/curl"
models_output="$(
  CODEX_TEST_CURL_ARGS="$TEST_ROOT/curl-args" \
  CODEX_TEST_CURL_CONFIG="$TEST_ROOT/curl-config" \
  PATH="$TEST_ROOT/fake-curl-bin:$PATH" \
  "$TOOL" models lab-api
)"
grep -q '^  model-a$' <<< "$models_output"
grep -q '^  model-b$' <<< "$models_output"
grep -Fxq -- '--config' "$TEST_ROOT/curl-args"
grep -Fxq -- '-' "$TEST_ROOT/curl-args"
if grep -q 'test-secret' "$TEST_ROOT/curl-args"; then
  printf 'API key leaked into curl process arguments\n' >&2
  exit 1
fi
grep -q 'Authorization: Bearer test-secret' "$TEST_ROOT/curl-config"

printf 'UMGPT_API_KEY=umgpt-test-secret\n' > "$CODEX_HOMES_ROOT/umgpt/.env"
printf 'UMGPT_API_KEY=umgpt-test-secret\n' > "$CODEX_HOMES_ROOT/umgpt-low/.env"
chmod 600 "$CODEX_HOMES_ROOT/umgpt/.env" "$CODEX_HOMES_ROOT/umgpt-low/.env"
umgpt_models_output="$(
  CODEX_TEST_CURL_ARGS="$TEST_ROOT/umgpt-curl-args" \
  CODEX_TEST_CURL_CONFIG="$TEST_ROOT/umgpt-curl-config" \
  PATH="$TEST_ROOT/fake-curl-bin:$PATH" \
  "$TOOL" models umgpt
)"
grep -q '^  gpt-6-sol$' <<< "$umgpt_models_output"
grep -q '^  o3$' <<< "$umgpt_models_output"
if grep -Eq '^  (claude-sonnet-5|gpt-image-2|text-embedding-3-large)$' \
  <<< "$umgpt_models_output"; then
  fail "models umgpt displayed a model outside the OpenAI text scope"
fi
grep -Fq 'Hidden by this identity scope: 5 model(s).' <<< "$umgpt_models_output"

umgpt_low_models_output="$(
  CODEX_TEST_CURL_ARGS="$TEST_ROOT/umgpt-low-curl-args" \
  CODEX_TEST_CURL_CONFIG="$TEST_ROOT/umgpt-low-curl-config" \
  PATH="$TEST_ROOT/fake-curl-bin:$PATH" \
  "$TOOL" models umgpt-low
)"
grep -q '^  gpt-6-sol$' <<< "$umgpt_low_models_output"
grep -q '^  claude-sonnet-5$' <<< "$umgpt_low_models_output"
if grep -Eq '^  (gpt-image-2|text-embedding-3-large)$' <<< "$umgpt_low_models_output"; then
  fail "models umgpt-low displayed a non-text model"
fi
grep -Fq 'Hidden by this identity scope: 2 model(s).' <<< "$umgpt_low_models_output"

# The checked-in model snapshot is generated from one raw catalog response,
# sorted and deduplicated, and never becomes a runtime input.
mkdir -p "$TEST_ROOT/snapshot-curl-bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$@" > "$CODEX_TEST_CURL_ARGS"' \
  'cat > "$CODEX_TEST_CURL_CONFIG"' \
  'printf "%s\n" "{\"data\":[{\"id\":\"model-b\"},{\"id\":\"gpt-image-2\"},{\"id\":\"o3\"},{\"id\":\"claude-sonnet-5\"},{\"id\":\"gpt-6-sol\"},{\"id\":\"model-a\"},{\"id\":\"text-embedding-3-large\"},{\"id\":\"o3\"}]}"' \
  > "$TEST_ROOT/snapshot-curl-bin/curl"
chmod +x "$TEST_ROOT/snapshot-curl-bin/curl"
snapshot_file="$TEST_ROOT/umgpt-models-snapshot.md"
snapshot_output="$(
  CODEX_UMGPT_SNAPSHOT_DATE=2026-09-24 \
  CODEX_TEST_CURL_ARGS="$TEST_ROOT/snapshot-curl-args" \
  CODEX_TEST_CURL_CONFIG="$TEST_ROOT/snapshot-curl-config" \
  PATH="$TEST_ROOT/snapshot-curl-bin:$PATH" \
  "$TOOL" snapshot-umgpt-models umgpt "$snapshot_file"
)"
grep -Fq "Updated U-M GPT model snapshot: $snapshot_file" <<< "$snapshot_output"
grep -Fq -- '- **Generated:** 2026-09-24' "$snapshot_file"
grep -Fq -- '- **Advertised IDs:** 7' "$snapshot_file"
grep -Fq -- '- **Matches `umgpt`:** 2' "$snapshot_file"
grep -Fq -- '- **Matches `umgpt-low`:** 5' "$snapshot_file"
grep -Fq -- '- **Excluded from both text scopes:** 2' "$snapshot_file"
assert_line_once "$snapshot_file" '| `gpt-6-sol` | Matches | Matches | GPT/o-series ID without image/embedding |'
assert_line_once "$snapshot_file" '| `o3` | Matches | Matches | GPT/o-series ID without image/embedding |'
assert_line_once "$snapshot_file" '| `claude-sonnet-5` | Does not match | Matches | Other ID without image/embedding |'
assert_line_once "$snapshot_file" '| `gpt-image-2` | Does not match | Does not match | ID contains image or embedding |'
snapshot_ids="$(sed -nE 's/^\| `([^`]*)` \|.*/\1/p' "$snapshot_file")"
[[ "$snapshot_ids" == $'claude-sonnet-5\ngpt-6-sol\ngpt-image-2\nmodel-a\nmodel-b\no3\ntext-embedding-3-large' ]] ||
  fail "snapshot model IDs were not sorted and deduplicated"
[[ "$snapshot_output" != *'umgpt-test-secret'* ]] ||
  fail "snapshot command output exposed the U-M GPT API key"
if grep -Fq 'umgpt-test-secret' "$snapshot_file" "$TEST_ROOT/snapshot-curl-args"; then
  fail "snapshot generation exposed the U-M GPT API key"
fi
if CODEX_TEST_CURL_ARGS="$TEST_ROOT/unexpected-snapshot-curl-args" \
  CODEX_TEST_CURL_CONFIG="$TEST_ROOT/unexpected-snapshot-curl-config" \
  PATH="$TEST_ROOT/snapshot-curl-bin:$PATH" \
  "$TOOL" snapshot-umgpt-models lab-api "$TEST_ROOT/generic-snapshot.md" \
  >/dev/null 2>&1; then
  fail "snapshot generation accepted a generic API identity"
fi
[[ ! -e "$TEST_ROOT/unexpected-snapshot-curl-args" ]] ||
  fail "rejected snapshot identity contacted the provider"

mkdir -p "$TEST_ROOT/invalid-snapshot-curl-bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'cat >/dev/null' \
  'printf "%s\n" "{\"data\":[{\"id\":\"bad model ID\"}]}"' \
  > "$TEST_ROOT/invalid-snapshot-curl-bin/curl"
chmod +x "$TEST_ROOT/invalid-snapshot-curl-bin/curl"
printf '%s\n' 'keep this snapshot' > "$TEST_ROOT/snapshot-sentinel.md"
if PATH="$TEST_ROOT/invalid-snapshot-curl-bin:$PATH" \
  "$TOOL" snapshot-umgpt-models umgpt "$TEST_ROOT/snapshot-sentinel.md" \
  >/dev/null 2>&1; then
  fail "snapshot generation accepted an invalid model ID"
fi
[[ "$(cat "$TEST_ROOT/snapshot-sentinel.md")" == 'keep this snapshot' ]] ||
  fail "failed snapshot generation replaced the existing output"

probe_secret='probe \\ " $ ` ! end'
CODEX_TEST_TOOL="$TOOL" \
CODEX_TEST_HOME="$HOME" \
CODEX_TEST_HOMES_ROOT="$CODEX_HOMES_ROOT" \
CODEX_TEST_PATH="$TEST_ROOT/fake-curl-bin:$PATH" \
CODEX_TEST_SECRET="$probe_secret" \
CODEX_TEST_BASE_URL="https://probe.example.test/v1/" \
CODEX_TEST_CURL_ARGS="$TEST_ROOT/probe-curl-args" \
CODEX_TEST_CURL_CONFIG="$TEST_ROOT/probe-curl-config" \
expect -c '
  set timeout 10
  spawn env -i \
    HOME=$env(CODEX_TEST_HOME) \
    CODEX_HOMES_ROOT=$env(CODEX_TEST_HOMES_ROOT) \
    PATH=$env(CODEX_TEST_PATH) \
    CODEX_TEST_CURL_ARGS=$env(CODEX_TEST_CURL_ARGS) \
    CODEX_TEST_CURL_CONFIG=$env(CODEX_TEST_CURL_CONFIG) \
    $env(CODEX_TEST_TOOL) probe-models $env(CODEX_TEST_BASE_URL)
  expect {
    -exact "API key for $env(CODEX_TEST_BASE_URL): " {}
    timeout { exit 124 }
    eof { exit 125 }
  }
  send -- "$env(CODEX_TEST_SECRET)\r"
  expect eof
  set child_status [wait]
  exit [lindex $child_status 3]
' > "$TEST_ROOT/probe-models-output"
if grep -Fq -- "$probe_secret" "$TEST_ROOT/probe-models-output"; then
  fail "probe-models echoed the entered secret"
fi
grep -q 'model-a' "$TEST_ROOT/probe-models-output" ||
  fail "probe-models did not print model-a"
grep -q 'model-b' "$TEST_ROOT/probe-models-output" ||
  fail "probe-models did not print model-b"
grep -Fq 'url = "https://probe.example.test/v1/models"' "$TEST_ROOT/probe-curl-config"
escaped_probe_secret="${probe_secret//\\/\\\\}"
escaped_probe_secret="${escaped_probe_secret//\"/\\\"}"
grep -Fq "header = \"Authorization: Bearer $escaped_probe_secret\"" \
  "$TEST_ROOT/probe-curl-config"
if grep -Fq -- "$probe_secret" "$TEST_ROOT/probe-curl-args"; then
  fail "probe-models leaked the API key into curl process arguments"
fi

project_output="$("$TOOL" project lab-api "$TEST_ROOT/project")"
project_workspace="$TEST_ROOT/project/.vscode/project.code-workspace"
[[ "$(grep -c ' vscode lab-api ' <<< "$project_output")" -eq 1 ]]
grep -q ' vscode lab-api .*/project$' <<< "$project_output"
grep -q 'CODEX_IDENTITY="lab-api"' "$TEST_ROOT/project/.envrc"
grep -q '^# Generated by codex-home. Contains machine-local paths; do not commit.$' \
  "$TEST_ROOT/project/.envrc"
grep -Fq "PATH_add \"$ROOT/bin\"" "$TEST_ROOT/project/.envrc"
grep -q '^// Generated by codex-home. Contains machine-local settings; do not commit.$' \
  "$project_workspace"
grep -Fq '"name": "project"' "$project_workspace"
grep -Fq '"window.title": "project [CODEX: LAB-API]"' "$project_workspace"
grep -Fq 'Git:      locally excluded by ' <<< "$project_output"
assert_line_once "$TEST_ROOT/project/.git/info/exclude" '/.envrc'
assert_line_once \
  "$TEST_ROOT/project/.git/info/exclude" \
  '/.vscode/project.code-workspace'
git -C "$TEST_ROOT/project" check-ignore -q -- .envrc
git -C "$TEST_ROOT/project" check-ignore -q -- .vscode/project.code-workspace
[[ -z "$(git -C "$TEST_ROOT/project" status --short)" ]] ||
  fail "generated project files appeared in Git status"

mkdir -p "$TEST_ROOT/nested-repo/projects/study [one]"
git -C "$TEST_ROOT/nested-repo" init -q
"$TOOL" project pro "$TEST_ROOT/nested-repo/projects/study [one]" >/dev/null
nested_workspace="$TEST_ROOT/nested-repo/projects/study [one]/.vscode/study [one].code-workspace"
tail -n +2 "$nested_workspace" | jq -e '
  .folders[0].name == "study [one]" and
  .settings["window.title"] == "study [one] [CODEX: PRO]"
' >/dev/null
git -C "$TEST_ROOT/nested-repo" check-ignore -q -- 'projects/study [one]/.envrc'
git -C "$TEST_ROOT/nested-repo" check-ignore -q -- \
  'projects/study [one]/.vscode/study [one].code-workspace'
[[ -z "$(git -C "$TEST_ROOT/nested-repo" status --short)" ]] ||
  fail "generated files in a nested project appeared in Git status"

mkdir -p "$TEST_ROOT/change-project"
git -C "$TEST_ROOT/change-project" init -q
"$TOOL" project lab-api "$TEST_ROOT/change-project" >/dev/null
change_project_abs="$(cd "$TEST_ROOT/change-project" && pwd -P)"
direnv allow "$change_project_abs" >/dev/null 2>&1
"$TOOL" project-change pro "$TEST_ROOT/change-project" >/dev/null
change_workspace="$TEST_ROOT/change-project/.vscode/change-project.code-workspace"
grep -q 'CODEX_IDENTITY="pro"' "$TEST_ROOT/change-project/.envrc"
grep -Fq '"window.title": "change-project [CODEX: PRO]"' "$change_workspace"
# Depending on the direnv version, a blocked .envrc either makes exec fail or
# runs the command without loading it. Neither may expose the changed identity.
blocked_identity="$(
  env -u CODEX_IDENTITY direnv exec "$change_project_abs" \
    sh -c 'printf %s "${CODEX_IDENTITY:-}"' 2>/dev/null
)" || true
[[ -z "$blocked_identity" ]] ||
  fail "project-change did not revoke approval for the replaced .envrc"
direnv allow "$change_project_abs" >/dev/null 2>&1
changed_identity="$(
  quiet_test_command direnv exec "$change_project_abs" sh -c 'printf %s "$CODEX_IDENTITY"'
)"
[[ "$changed_identity" == "pro" ]] || fail "project-change selected the wrong identity"
"$TOOL" project-reset "$TEST_ROOT/change-project" >/dev/null
[[ ! -e "$TEST_ROOT/change-project/.envrc" ]]
[[ ! -e "$change_workspace" ]]
if grep -Fqx '/.envrc' "$TEST_ROOT/change-project/.git/info/exclude"; then
  fail "project-reset left the .envrc Git exclusion behind"
fi
if grep -Fqx '/.vscode/change-project.code-workspace' \
  "$TEST_ROOT/change-project/.git/info/exclude"; then
  fail "project-reset left the workspace Git exclusion behind"
fi
[[ -f "$CODEX_HOMES_ROOT/pro/config.toml" ]] ||
  fail "project-reset changed the selected identity home"

mkdir -p "$TEST_ROOT/legacy-project"
git -C "$TEST_ROOT/legacy-project" init -q
"$TOOL" project lab-api "$TEST_ROOT/legacy-project" >/dev/null
legacy_workspace="$TEST_ROOT/legacy-project/.vscode/codex-context.code-workspace"
rm -f "$TEST_ROOT/legacy-project/.vscode/legacy-project.code-workspace"
printf '%s\n' \
  '{' \
  '  "folders": [' \
  '    { "path": ".." }' \
  '  ],' \
  '  "settings": {' \
  '    "window.title": "[CODEX: API: LAB-API] ${dirty}${activeEditorShort}${separator}${rootName}${separator}${appName}",' \
  '    "workbench.colorCustomizations": {' \
  '      "statusBar.background": "#B35C00",' \
  '      "statusBar.foreground": "#FFFFFF",' \
  '      "statusBar.noFolderBackground": "#B35C00",' \
  '      "statusBar.debuggingBackground": "#B35C00"' \
  '    }' \
  '  }' \
  '}' \
  > "$legacy_workspace"
legacy_exclude="$TEST_ROOT/legacy-project/.git/info/exclude"
awk '$0 != "/.vscode/legacy-project.code-workspace" { print }' \
  "$legacy_exclude" > "$legacy_exclude.tmp"
printf '%s\n' '/.vscode/codex-context.code-workspace' >> "$legacy_exclude.tmp"
mv "$legacy_exclude.tmp" "$legacy_exclude"
mkdir -p "$TEST_ROOT/direnv-deny-bin"
cat > "$TEST_ROOT/direnv-deny-bin/direnv" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "deny" ]]; then
  case "$CODEX_TEST_DIRENV_DENY_ERROR" in
    missing)
      printf 'direnv: error remove %s/direnv/allow/deadbeef: no such file or directory\n' \
        "$XDG_DATA_HOME" >&2
      ;;
    permission)
      printf 'direnv: error remove %s/direnv/allow/deadbeef: permission denied\n' \
        "$XDG_DATA_HOME" >&2
      ;;
  esac
  exit 1
fi
exec "$CODEX_TEST_REAL_DIRENV" "$@"
EOF
chmod +x "$TEST_ROOT/direnv-deny-bin/direnv"
# A missing approval file must not prevent context replacement.
CODEX_TEST_DIRENV_DENY_ERROR=missing \
  CODEX_TEST_REAL_DIRENV="$(command -v direnv)" \
  PATH="$TEST_ROOT/direnv-deny-bin:$PATH" \
  "$TOOL" project-change pro "$TEST_ROOT/legacy-project" >/dev/null
grep -q 'CODEX_IDENTITY="pro"' "$TEST_ROOT/legacy-project/.envrc" ||
  fail "project-change did not accept the generated codex-context.code-workspace"
[[ ! -e "$legacy_workspace" ]] ||
  fail "project-change did not remove codex-context.code-workspace"
grep -Fq '"window.title": "legacy-project [CODEX: PRO]"' \
  "$TEST_ROOT/legacy-project/.vscode/legacy-project.code-workspace"
if grep -Fqx '/.vscode/codex-context.code-workspace' "$legacy_exclude"; then
  fail "project-change left the codex-context.code-workspace Git exclusion behind"
fi

mkdir -p "$TEST_ROOT/deny-error-project"
"$TOOL" project pro "$TEST_ROOT/deny-error-project" >/dev/null
if CODEX_TEST_DIRENV_DENY_ERROR=permission \
  CODEX_TEST_REAL_DIRENV="$(command -v direnv)" \
  PATH="$TEST_ROOT/direnv-deny-bin:$PATH" \
  "$TOOL" project-reset "$TEST_ROOT/deny-error-project" >/dev/null 2>&1; then
  fail "project-reset ignored a direnv permission error"
fi
[[ -f "$TEST_ROOT/deny-error-project/.envrc" ]] ||
  fail "project-reset removed files after direnv denial failed"

mkdir -p "$TEST_ROOT/modified-project"
"$TOOL" project pro "$TEST_ROOT/modified-project" >/dev/null
printf '%s\n' '# local customization' >> "$TEST_ROOT/modified-project/.envrc"
if "$TOOL" project-change business "$TEST_ROOT/modified-project" >/dev/null 2>&1; then
  fail "project-change replaced a modified generated .envrc"
fi
grep -Fqx '# local customization' "$TEST_ROOT/modified-project/.envrc"

mkdir -p "$TEST_ROOT/tracked-project"
git -C "$TEST_ROOT/tracked-project" init -q
"$TOOL" project pro "$TEST_ROOT/tracked-project" >/dev/null
git -C "$TEST_ROOT/tracked-project" add -f -- \
  .envrc .vscode/tracked-project.code-workspace
if "$TOOL" project-reset "$TEST_ROOT/tracked-project" >/dev/null 2>&1; then
  fail "project-reset removed tracked project files"
fi
[[ -f "$TEST_ROOT/tracked-project/.envrc" ]]
[[ -f "$TEST_ROOT/tracked-project/.vscode/tracked-project.code-workspace" ]]

mkdir -p "$TEST_ROOT/symlink-envrc" "$TEST_ROOT/symlink-workspace/.vscode" \
  "$TEST_ROOT/symlink-vscode-target" "$TEST_ROOT/symlink-vscode"
ln -s "$TEST_ROOT/outside-envrc" "$TEST_ROOT/symlink-envrc/.envrc"
if "$TOOL" project pro "$TEST_ROOT/symlink-envrc" >/dev/null 2>&1; then
  fail "project followed a dangling .envrc symlink"
fi
[[ ! -e "$TEST_ROOT/outside-envrc" ]]
ln -s "$TEST_ROOT/outside-workspace" \
  "$TEST_ROOT/symlink-workspace/.vscode/symlink-workspace.code-workspace"
if "$TOOL" project pro "$TEST_ROOT/symlink-workspace" >/dev/null 2>&1; then
  fail "project followed a dangling workspace symlink"
fi
[[ ! -e "$TEST_ROOT/outside-workspace" ]]
ln -s "$TEST_ROOT/symlink-vscode-target" "$TEST_ROOT/symlink-vscode/.vscode"
if "$TOOL" project pro "$TEST_ROOT/symlink-vscode" >/dev/null 2>&1; then
  fail "project wrote through a symlinked .vscode directory"
fi
[[ ! -e "$TEST_ROOT/symlink-vscode/.envrc" ]]
[[ ! -e "$TEST_ROOT/symlink-vscode-target/symlink-vscode.code-workspace" ]]

if CODEX_VSCODE_CLI=/usr/bin/true \
  "$TOOL" vscode-project "$TEST_ROOT/project" >/dev/null 2>&1; then
  fail "vscode-project accepted an unapproved .envrc"
fi

direnv allow "$TEST_ROOT/project" >/dev/null 2>&1
cd "$TEST_ROOT/project"
actual="$(quiet_test_command direnv exec . sh -c 'printf "%s|%s|%s" "$CODEX_IDENTITY" "$CODEX_HOME" "$LAB_API_KEY"')"
[[ "$actual" == "lab-api|$CODEX_HOMES_ROOT/lab-api|test-secret" ]]

current="$(quiet_test_command direnv exec . "$TOOL" current)"
grep -q 'Codex identity : API: LAB-API' <<< "$current"
grep -q 'API key env    : LAB_API_KEY (loaded)' <<< "$current"

mkdir -p "$TEST_ROOT/fake-bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$@" > "$CODEX_TEST_CODE_ARGS"' \
  'last_arg=""' \
  'for arg in "$@"; do last_arg="$arg"; done' \
  'if [[ -n "${CODEX_TEST_REVIEW_SNAPSHOT:-}" ]]; then' \
  '  cp "$last_arg" "$CODEX_TEST_REVIEW_SNAPSHOT"' \
  'fi' \
  > "$TEST_ROOT/fake-bin/code"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$@" > "$CODEX_TEST_CODEX_ARGS"' \
  'printf "%s|%s|%s\n" "$CODEX_HOME" "$CODEX_IDENTITY" "${LAB_API_KEY:-}" > "$CODEX_TEST_CODEX_ENV"' \
  'if [[ -n "${CODEX_TEST_CODEX_INPUT:-}" ]]; then' \
  '  IFS= read -r reply' \
  '  printf "%s\n" "$reply" > "$CODEX_TEST_CODEX_INPUT"' \
  'fi' \
  'exit "${CODEX_TEST_CODEX_EXIT:-0}"' \
  > "$TEST_ROOT/fake-bin/codex"
chmod +x "$TEST_ROOT/fake-bin/code" "$TEST_ROOT/fake-bin/codex"

run_output="$(
  CODEX_IDENTITY=pro \
  CODEX_TEST_CODEX_ARGS="$TEST_ROOT/codex-args" \
  CODEX_TEST_CODEX_ENV="$TEST_ROOT/codex-env" \
  PATH="$TEST_ROOT/fake-bin:$PATH" \
  "$TOOL" run lab-api --version 2>&1
)"
[[ "$(grep -Fc 'Codex identity: API: LAB-API' <<< "$run_output")" -eq 1 ]] ||
  fail "run printed the identity banner more or less than once"
grep -Fxq -- '--version' "$TEST_ROOT/codex-args"
grep -Fxq -- "$CODEX_HOMES_ROOT/lab-api|lab-api|test-secret" "$TEST_ROOT/codex-env"
[[ "$(cat "$TEST_ROOT/codex-args")" == "--version" ]] ||
  fail "run changed arguments for redirected output"
[[ "$run_output" != *$'\033'* ]] ||
  fail "run emitted terminal controls into redirected output"

umgpt_run_output="$(
  CODEX_TEST_CODEX_ARGS="$TEST_ROOT/umgpt-codex-args" \
  CODEX_TEST_CODEX_ENV="$TEST_ROOT/umgpt-codex-env" \
  PATH="$TEST_ROOT/fake-bin:$PATH" \
  "$TOOL" run umgpt --version 2>&1
)"
grep -Fq 'Codex identity: U-M GPT (Azure OpenAI): UMGPT' <<< "$umgpt_run_output"
[[ "$(cat "$TEST_ROOT/umgpt-codex-args")" == $'--model\n'"$repository_openai_model"$'\n--version' ]] ||
  fail "run did not pin the configured U-M GPT OpenAI model"

CODEX_TEST_CODEX_ARGS="$TEST_ROOT/umgpt-override-args" \
  CODEX_TEST_CODEX_ENV="$TEST_ROOT/umgpt-override-env" \
  PATH="$TEST_ROOT/fake-bin:$PATH" \
  "$TOOL" run umgpt --model gpt-session-test 'test prompt' >/dev/null 2>&1
[[ "$(cat "$TEST_ROOT/umgpt-override-args")" == $'--model\ngpt-session-test\ntest prompt' ]] ||
  fail "run did not validate and pass an allowed U-M GPT model override"

if CODEX_TEST_CODEX_ARGS="$TEST_ROOT/umgpt-rejected-args" \
  CODEX_TEST_CODEX_ENV="$TEST_ROOT/umgpt-rejected-env" \
  PATH="$TEST_ROOT/fake-bin:$PATH" \
  "$TOOL" run umgpt --model claude-sonnet-5 >/dev/null 2>&1; then
  fail "run allowed a Claude model in the OpenAI-only U-M GPT identity"
fi
[[ ! -e "$TEST_ROOT/umgpt-rejected-args" ]] ||
  fail "run invoked Codex after rejecting a U-M GPT model"
if CODEX_TEST_CODEX_ARGS="$TEST_ROOT/umgpt-config-bypass-args" \
  CODEX_TEST_CODEX_ENV="$TEST_ROOT/umgpt-config-bypass-env" \
  PATH="$TEST_ROOT/fake-bin:$PATH" \
  "$TOOL" run umgpt -c 'model="claude-sonnet-5"' >/dev/null 2>&1; then
  fail "run allowed a config override that bypasses the U-M GPT model scope"
fi

umgpt_low_run_output="$(
  CODEX_TEST_CODEX_ARGS="$TEST_ROOT/umgpt-low-codex-args" \
  CODEX_TEST_CODEX_ENV="$TEST_ROOT/umgpt-low-codex-env" \
  PATH="$TEST_ROOT/fake-bin:$PATH" \
  "$TOOL" run umgpt-low --model claude-opus-5-5 2>&1
)"
grep -Fq 'LOW-SENSITIVITY DATA ONLY' <<< "$umgpt_low_run_output"
[[ "$(cat "$TEST_ROOT/umgpt-low-codex-args")" == $'--model\nclaude-opus-5-5' ]] ||
  fail "run did not pass an allowed low-sensitivity U-M GPT model override"
if CODEX_TEST_CODEX_ARGS="$TEST_ROOT/umgpt-low-image-args" \
  CODEX_TEST_CODEX_ENV="$TEST_ROOT/umgpt-low-image-env" \
  PATH="$TEST_ROOT/fake-bin:$PATH" \
  "$TOOL" run umgpt-low --model gpt-image-2 >/dev/null 2>&1; then
  fail "run accepted an image-generation model for the low-sensitivity identity"
fi

# A configured project's environment supplies the name when it is omitted.
run_from_project() {
  CODEX_TEST_CODEX_ARGS="$TEST_ROOT/project-run-args" \
    CODEX_TEST_CODEX_ENV="$TEST_ROOT/project-run-env" \
    PATH="$TEST_ROOT/fake-bin:$PATH" \
    quiet_test_command direnv exec . "$TOOL" run "$@" >/dev/null
  grep -Fxq -- "$CODEX_HOMES_ROOT/lab-api|lab-api|test-secret" \
    "$TEST_ROOT/project-run-env" || fail "run did not use the active project context"
}

run_from_project
[[ -z "$(cat "$TEST_ROOT/project-run-args")" ]] ||
  fail "run added arguments when only the project context was requested"
run_from_project --model test-model 'test prompt'
[[ "$(cat "$TEST_ROOT/project-run-args")" == $'--model\ntest-model\ntest prompt' ]] ||
  fail "run did not preserve options and the prompt for the project context"
run_from_project -- resume --last
[[ "$(cat "$TEST_ROOT/project-run-args")" == $'resume\n--last' ]] ||
  fail "run did not pass the subcommand after --"
run_from_project -- 'explain this project'
[[ "$(cat "$TEST_ROOT/project-run-args")" == 'explain this project' ]] ||
  fail "run did not preserve the prompt after --"

# A missing or invalid context must not silently launch another account.
if missing_context="$(
  env -u CODEX_IDENTITY \
    CODEX_TEST_CODEX_ARGS="$TEST_ROOT/unexpected-run-args" \
    CODEX_TEST_CODEX_ENV="$TEST_ROOT/unexpected-run-env" \
    PATH="$TEST_ROOT/fake-bin:$PATH" "$TOOL" run 2>&1
)"; then
  fail "run accepted a missing project context"
fi
grep -Fq 'no active project context' <<< "$missing_context"
[[ ! -e "$TEST_ROOT/unexpected-run-env" ]] || fail "run launched Codex without a context"
if CODEX_IDENTITY=missing "$TOOL" run >/dev/null 2>&1; then
  fail "run accepted an identity that does not exist"
fi

# A real pseudoterminal checks input, arguments, title cleanup, and exit status.
# The Codex double is local; these cases never open a provider connection.
for run_case in pro lab-api dumb project; do
  run_name="$run_case"
  run_term=xterm-256color
  run_exit=0
  if [[ "$run_case" == "lab-api" ]]; then run_exit=23; fi
  if [[ "$run_case" == "dumb" ]]; then
    run_name=pro
    run_term=dumb
  fi
  if [[ "$run_case" == "project" ]]; then run_name=lab-api; fi
  cp "$CODEX_HOMES_ROOT/$run_name/config.toml" "$TEST_ROOT/run-config-before"
  if CODEX_TEST_TOOL="$TOOL" \
    CODEX_IDENTITY="$run_name" \
    CODEX_TEST_RUN_CASE="$run_case" \
    CODEX_TEST_RUN_NAME="$run_name" \
    CODEX_TEST_CODEX_ARGS="$TEST_ROOT/tty-args" \
    CODEX_TEST_CODEX_ENV="$TEST_ROOT/tty-env" \
    CODEX_TEST_CODEX_INPUT="$TEST_ROOT/tty-input" \
    CODEX_TEST_CODEX_EXIT="$run_exit" \
    TERM="$run_term" PATH="$TEST_ROOT/fake-bin:$PATH" \
    expect -c '
      set timeout 10
      if {$env(CODEX_TEST_RUN_CASE) eq "project"} {
        spawn -noecho $env(CODEX_TEST_TOOL) run --model test-model {test prompt}
      } else {
        spawn -noecho $env(CODEX_TEST_TOOL) run $env(CODEX_TEST_RUN_NAME) --model test-model {test prompt}
      }
      expect {
        -exact {Codex identity: } {}
        -exact {[CODEX: } {}
        timeout { exit 124 }
        eof { exit 125 }
      }
      send -- "terminal input\r"
      expect eof
      exit [lindex [wait] 3]
    ' > "$TEST_ROOT/tty-output"; then
    actual_exit=0
  else
    actual_exit=$?
  fi
  [[ "$actual_exit" -eq "$run_exit" ]] || fail "run lost the Codex exit status"
  [[ "$(cat "$TEST_ROOT/tty-input")" == "terminal input" ]] ||
    fail "run did not preserve interactive stdin"
  grep -Fxq -- 'test prompt' "$TEST_ROOT/tty-args"
  cmp -s "$CODEX_HOMES_ROOT/$run_name/config.toml" "$TEST_ROOT/run-config-before" ||
    fail "run changed the identity's saved configuration"
  if [[ "$run_case" == "dumb" ]]; then
    ! grep -Fq $'\033' "$TEST_ROOT/tty-output" ||
      fail "run emitted terminal controls for TERM=dumb"
    ! grep -Fq 'tui.terminal_title' "$TEST_ROOT/tty-args" ||
      fail "run changed title settings for TERM=dumb"
  else
    run_upper="$(printf '%s' "$run_name" | tr '[:lower:]' '[:upper:]')"
    grep -Fq "$(printf '\033]0;[CODEX: %s]\007' "$run_upper")" "$TEST_ROOT/tty-output" ||
      fail "run did not label the terminal with the selected context"
    grep -Fq "$(printf '\033[1;7m  [CODEX: %s]' "$run_upper")" "$TEST_ROOT/tty-output" ||
      fail "run did not print a prominent context banner"
    grep -Fq $'\033]0;\007\033[23;0t' "$TEST_ROOT/tty-output" ||
      fail "run left a stale context title after Codex exited"
    grep -Fxq 'tui.terminal_title=[]' "$TEST_ROOT/tty-args" ||
      fail "run did not stop Codex overwriting the context title"
  fi
done

CODEX_TEST_CODE_ARGS="$TEST_ROOT/code-args" \
  PATH="$TEST_ROOT/fake-bin:$PATH" \
  quiet_test_command "$TOOL" vscode lab-api "$TEST_ROOT/project" >/dev/null
grep -Fxq -- '--new-window' "$TEST_ROOT/code-args"
grep -Fxq -- '--user-data-dir' "$TEST_ROOT/code-args"
grep -Fxq -- "$CODEX_HOMES_ROOT/lab-api/vscode-user-data" "$TEST_ROOT/code-args"
grep -Fq '/.vscode/project.code-workspace' "$TEST_ROOT/code-args"

CODEX_TEST_CODE_ARGS="$TEST_ROOT/code-project-args" \
  PATH="$TEST_ROOT/fake-bin:$PATH" \
  quiet_test_command "$TOOL" vscode-project "$TEST_ROOT/project" >/dev/null
grep -Fxq -- "$CODEX_HOMES_ROOT/lab-api/vscode-user-data" "$TEST_ROOT/code-project-args"

CODEX_TEST_CODE_ARGS="$TEST_ROOT/code-review-args" \
  CODEX_TEST_REVIEW_SNAPSHOT="$TEST_ROOT/review-snapshot" \
  PATH="$TEST_ROOT/fake-bin:$PATH" \
  "$TOOL" project-review "$TEST_ROOT/project" >/dev/null
grep -Fxq -- '--new-window' "$TEST_ROOT/code-review-args"
grep -Fxq -- '--wait' "$TEST_ROOT/code-review-args"
grep -Fxq -- '--disable-extensions' "$TEST_ROOT/code-review-args"
grep -Eq '/project\.envrc-review\.sh$' "$TEST_ROOT/code-review-args"
cmp -s "$TEST_ROOT/project/.envrc" "$TEST_ROOT/review-snapshot" ||
  fail "project-review did not open an exact snapshot of .envrc"
review_snapshot_path="$(tail -n 1 "$TEST_ROOT/code-review-args")"
[[ ! -e "$review_snapshot_path" ]] ||
  fail "project-review left its temporary snapshot behind"

bash "$ROOT/tests/identity-config.sh"
bash "$ROOT/tests/model-catalog.sh"
bash "$ROOT/tests/project-files.sh"
bash "$ROOT/tests/project-launch.sh"

if [[ "$(uname -s)" == "Darwin" ]]; then
  bash "$ROOT/tests/macos-dock.sh"
  bash "$ROOT/tests/macos-open-with.sh"
  CODEX_MACOS_APP_DIR="$TEST_ROOT/apps" \
    CODEX_MACOS_SERVICES_DIR="$TEST_ROOT/services" \
    CODEX_MACOS_SKIP_REGISTER=1 \
    "$ROOT/bin/install-macos-open-with" >/dev/null 2>&1
  test_app="$TEST_ROOT/apps/Codex Project.app"
  test_workflow="$TEST_ROOT/services/Open in Codex Project.workflow"
  workflow_plist="$test_workflow/Contents/Info.plist"
  workflow_document="$test_workflow/Contents/Resources/document.wflow"
  [[ -x "$test_app/Contents/Resources/codex-home" ]]
  cmp -s \
    "$ROOT/config/umgpt-models.toml" \
    "$test_app/Contents/config/umgpt-models.toml" ||
    fail "Finder launcher did not bundle U-M GPT model defaults"
  plutil -lint "$workflow_plist" "$workflow_document" >/dev/null
  [[ "$(plutil -extract NSServices.0.NSMenuItem.default raw "$workflow_plist")" == 'Open in Codex Project' ]]
  [[ "$(plutil -extract NSServices.0.NSRequiredContext.NSApplicationIdentifier raw "$workflow_plist")" == 'com.apple.finder' ]]
  [[ "$(plutil -extract NSServices.0.NSSendFileTypes.0 raw "$workflow_plist")" == 'public.folder' ]]
  [[ "$(plutil -extract workflowMetaData.serviceInputTypeIdentifier raw "$workflow_document")" == 'com.apple.Automator.fileSystemObject.folder' ]]
  [[ "$(plutil -extract actions.0.action.ActionParameters.inputMethod raw "$workflow_document")" == 1 ]]
  [[ "$(plutil -extract actions.0.action.ActionParameters.shell raw "$workflow_document")" == /bin/bash ]]
  plutil -p "$test_app/Contents/Info.plist" | grep -q 'public.folder'
  osadecompile "$test_app/Contents/Resources/Scripts/main.scpt" \
    > "$TEST_ROOT/codex-project-app.applescript"
  grep -Fq '"list", "--names"' "$TEST_ROOT/codex-project-app.applescript"
  grep -Fq 'Open with current Codex context' "$TEST_ROOT/codex-project-app.applescript"
  grep -Fq 'project-change' "$TEST_ROOT/codex-project-app.applescript"
  grep -Fq 'project-reset' "$TEST_ROOT/codex-project-app.applescript"
  grep -Fq 'project-review' "$TEST_ROOT/codex-project-app.applescript"
  grep -Fq 'Review in VS Code' "$TEST_ROOT/codex-project-app.applescript"
  grep -Fq 'Review Again' "$TEST_ROOT/codex-project-app.applescript"
  grep -Fq 'Approve & Open' "$TEST_ROOT/codex-project-app.applescript"
  grep -Fq 'CODEX_VSCODE_DOCK_LABEL=1' "$TEST_ROOT/codex-project-app.applescript"

  # Call compiled non-UI handlers with a recorder instead of opening an editor.
  apple_mock="$TEST_ROOT/"'helper $dollar & quote'"'"' [x]'
  printf '%s\n' '#!/bin/bash' \
    'printf "%s\0" "$@" > "$CODEX_TEST_APPLE_ARGS"' \
    'printf "%s\n" "${CODEX_VSCODE_DOCK_LABEL:-}" "${CODEX_TEST_LOGIN_SHELL:-}" > "$CODEX_TEST_APPLE_ENV"' \
    'printf "%s\n" "handler output"' \
    'exit "${CODEX_TEST_APPLE_EXIT:-0}"' > "$apple_mock"
  chmod +x "$apple_mock"
  mkdir -p "$TEST_ROOT/apple-shell"
  printf '%s\n' 'export CODEX_TEST_LOGIN_SHELL=loaded' > "$TEST_ROOT/apple-shell/.zprofile"
  apple_folder="$TEST_ROOT/"'folder $literal & quote'"'"' [x]'
  apple_argument='$(exit 91); `exit 92` "quoted"'
  CODEX_TEST_APPLE_ARGS="$TEST_ROOT/apple-args" \
    CODEX_TEST_APPLE_ENV="$TEST_ROOT/apple-env" \
    ZDOTDIR="$TEST_ROOT/apple-shell" \
    osascript - "$test_app/Contents/Resources/Scripts/main.scpt" \
      "$apple_mock" "$apple_folder" "$apple_argument" <<'APPLESCRIPT' > "$TEST_ROOT/apple-output"
on run arguments
  set appScript to «event sysoload» (POSIX file (item 1 of arguments))
  return appScript's runCommand({item 2 of arguments, item 3 of arguments, item 4 of arguments, ""})
end run
APPLESCRIPT
  printf '%s\0' "$apple_folder" "$apple_argument" '' > "$TEST_ROOT/apple-expected-args"
  cmp -s "$TEST_ROOT/apple-args" "$TEST_ROOT/apple-expected-args" ||
    fail "AppleScript command runner split or expanded arguments"
  grep -Fxq 'loaded' "$TEST_ROOT/apple-env" || fail "AppleScript command runner skipped the login shell"
  grep -Fxq 'handler output' "$TEST_ROOT/apple-output" || fail "AppleScript command runner lost stdout"

  CODEX_TEST_APPLE_ARGS="$TEST_ROOT/apple-args" \
    CODEX_TEST_APPLE_ENV="$TEST_ROOT/apple-env" CODEX_VSCODE_DOCK_LABEL=0 \
    ZDOTDIR="$TEST_ROOT/apple-shell" \
    osascript - "$test_app/Contents/Resources/Scripts/main.scpt" \
      "$apple_mock" "$apple_folder" <<'APPLESCRIPT' >/dev/null
on run arguments
  set appScript to «event sysoload» (POSIX file (item 1 of arguments))
  appScript's launchProject(item 2 of arguments, item 3 of arguments)
end run
APPLESCRIPT
  printf '%s\0' vscode-project "$apple_folder" > "$TEST_ROOT/apple-expected-args"
  cmp -s "$TEST_ROOT/apple-args" "$TEST_ROOT/apple-expected-args" ||
    fail "AppleScript launch handler changed helper arguments"
  [[ "$(head -n 1 "$TEST_ROOT/apple-env")" == 1 ]] ||
    fail "AppleScript launch handler did not require Dock identity labels"

  CODEX_TEST_APPLE_ARGS="$TEST_ROOT/apple-args" \
    CODEX_TEST_APPLE_ENV="$TEST_ROOT/apple-env" CODEX_TEST_APPLE_EXIT=23 \
    ZDOTDIR="$TEST_ROOT/apple-shell" \
    osascript - "$test_app/Contents/Resources/Scripts/main.scpt" \
      "$apple_mock" <<'APPLESCRIPT' >/dev/null
on run arguments
  set appScript to «event sysoload» (POSIX file (item 1 of arguments))
  try
    appScript's runCommand({item 2 of arguments})
  on error errorMessage number errorNumber
    if errorNumber is 23 then return
    error errorMessage number errorNumber
  end try
  error "AppleScript command runner hid the helper failure"
end run
APPLESCRIPT

  mkdir -p "$TEST_ROOT/app-project"
  "$test_app/Contents/Resources/codex-home" \
    project pro "$TEST_ROOT/app-project" >/dev/null
  [[ -f "$TEST_ROOT/app-project/.vscode/app-project.code-workspace" ]]
  bundle_resources="$(cd "$test_app/Contents/Resources" && pwd -P)"
  grep -Fq \
    "PATH_add \"$bundle_resources\"" \
    "$TEST_ROOT/app-project/.envrc"
  app_project_abs="$(cd "$TEST_ROOT/app-project" && pwd -P)"
  direnv allow "$app_project_abs" >/dev/null 2>&1
  bundled_helper="$(
    quiet_test_command direnv exec "$app_project_abs" sh -c 'command -v codex-home'
  )"
  [[ "$bundled_helper" == "$bundle_resources/codex-home" ]] ||
    fail "the bundled helper was not added to PATH"

  CODEX_MACOS_APP_DIR="$TEST_ROOT/apps" \
    CODEX_MACOS_SERVICES_DIR="$TEST_ROOT/services" \
    CODEX_MACOS_SKIP_REGISTER=1 \
    "$ROOT/bin/install-macos-open-with" >/dev/null 2>&1
  [[ -x "$test_app/Contents/Resources/codex-home" ]]
  find "$TEST_ROOT/apps/.codex-project-backups" -maxdepth 1 -type d \
    -name '*.app.backup' -print -quit | grep -q . ||
    fail "reinstall did not retain a non-application backup"
  find "$TEST_ROOT/services/.codex-project-backups" -maxdepth 1 -type d \
    -name '*.workflow.backup' -print -quit | grep -q . ||
    fail "reinstall did not retain a Quick Action backup"

  # Refuse an unrelated service before touching the existing application.
  mkdir -p "$TEST_ROOT/foreign-services/Open in Codex Project.workflow"
  installed_app_inode="$(stat -f %i "$test_app")"
  if CODEX_MACOS_APP_DIR="$TEST_ROOT/apps" \
    CODEX_MACOS_SERVICES_DIR="$TEST_ROOT/foreign-services" \
    CODEX_MACOS_SKIP_REGISTER=1 \
    "$ROOT/bin/install-macos-open-with" >"$TEST_ROOT/foreign-workflow-error" 2>&1; then
    fail "installer replaced an unrelated Quick Action"
  fi
  grep -Fq 'refusing to replace an unrelated Quick Action' "$TEST_ROOT/foreign-workflow-error"
  if CODEX_MACOS_APP_DIR="$TEST_ROOT/apps" \
    CODEX_MACOS_SERVICES_DIR="$TEST_ROOT/foreign-services" \
    CODEX_MACOS_TRASH_DIR="$TEST_ROOT/trash" \
    CODEX_MACOS_SKIP_REGISTER=1 \
    "$ROOT/bin/uninstall-macos-open-with" >"$TEST_ROOT/foreign-workflow-error" 2>&1; then
    fail "uninstaller removed an unrelated Quick Action"
  fi
  [[ "$(stat -f %i "$test_app")" == "$installed_app_inode" ]] ||
    fail "foreign Quick Action refusal changed the installed app"
  [[ -d "$TEST_ROOT/foreign-services/Open in Codex Project.workflow" ]]

  CODEX_MACOS_APP_DIR="$TEST_ROOT/apps" \
    CODEX_MACOS_SERVICES_DIR="$TEST_ROOT/services" \
    CODEX_MACOS_TRASH_DIR="$TEST_ROOT/trash" \
    CODEX_MACOS_SKIP_REGISTER=1 \
    "$ROOT/bin/uninstall-macos-open-with" >/dev/null
  [[ ! -e "$test_app" ]]
  [[ ! -e "$test_workflow" ]]
  find "$TEST_ROOT/trash" -maxdepth 1 -type d -name 'Codex Project.*.app' \
    -print -quit | grep -q . || fail "uninstaller did not move the app to Trash"
  find "$TEST_ROOT/trash" -maxdepth 1 -type d -name 'Open in Codex Project.*.workflow' \
    -print -quit | grep -q . || fail "uninstaller did not move the Quick Action to Trash"
  "$TOOL" project-reset "$TEST_ROOT/app-project" >/dev/null
  [[ ! -e "$TEST_ROOT/app-project/.envrc" ]] ||
    fail "repository helper did not reset a context created by the bundled helper"

  # Quick Actions preserve shell metacharacters in app and selected-folder paths.
  # Record open's arguments without launching an application.
  quoted_apps="$TEST_ROOT/"'apps $one [x] & quoted'
  CODEX_MACOS_APP_DIR="$quoted_apps" \
    CODEX_MACOS_SERVICES_DIR="$TEST_ROOT/quoted-services" \
    CODEX_MACOS_SKIP_REGISTER=1 \
    "$ROOT/bin/install-macos-open-with" >/dev/null 2>&1
  quoted_apps="$(cd "$quoted_apps" && pwd -P)"
  quoted_workflow="$TEST_ROOT/quoted-services/Open in Codex Project.workflow"
  workflow_command="$(plutil -extract actions.0.action.ActionParameters.COMMAND_STRING raw \
    "$quoted_workflow/Contents/Resources/document.wflow")"
  printf -v expected_workflow_command '[[ "$#" -gt 0 ]] || exit 0\nexec /usr/bin/open -a %q -- "$@"' \
    "$quoted_apps/Codex Project.app"
  [[ "$workflow_command" == "$expected_workflow_command" ]] ||
    fail "Quick Action does not target the exact quoted installed app"
  workflow_mock="$TEST_ROOT/quick-action-open-mock"
  printf '%s\n' '#!/bin/bash' \
    'printf "%s\0" "$@" > "$CODEX_QUICK_ACTION_ARGS"' \
    'exit "${CODEX_QUICK_ACTION_EXIT:-0}"' > "$workflow_mock"
  chmod +x "$workflow_mock"
  printf -v workflow_mock_quoted '%q' "$workflow_mock"
  workflow_mock_command="${workflow_command/exec \/usr\/bin\/open/exec $workflow_mock_quoted}"
  folder_one="$TEST_ROOT/"'folder $one [x]'
  folder_two="$TEST_ROOT/"'folder two & quoted'
  CODEX_QUICK_ACTION_ARGS="$TEST_ROOT/workflow-args" \
    /bin/bash -c "$workflow_mock_command" -- "$folder_one" "$folder_two"
  printf '%s\0' -a "$quoted_apps/Codex Project.app" -- "$folder_one" "$folder_two" \
    > "$TEST_ROOT/workflow-expected-args"
  cmp -s "$TEST_ROOT/workflow-args" "$TEST_ROOT/workflow-expected-args" ||
    fail "Quick Action split or changed selected folder arguments"
  if CODEX_QUICK_ACTION_ARGS="$TEST_ROOT/workflow-args" CODEX_QUICK_ACTION_EXIT=23 \
    /bin/bash -c "$workflow_mock_command" -- "$folder_one"; then
    fail "Quick Action hid an open failure"
  else
    [[ "$?" == 23 ]] || fail "Quick Action changed the open failure status"
  fi
  # An orphaned workflow must still be removable when the app is absent.
  mv "$quoted_apps/Codex Project.app" "$TEST_ROOT/quoted-app.saved"
  CODEX_MACOS_APP_DIR="$quoted_apps" \
    CODEX_MACOS_SERVICES_DIR="$TEST_ROOT/quoted-services" \
    CODEX_MACOS_TRASH_DIR="$TEST_ROOT/trash" \
    CODEX_MACOS_SKIP_REGISTER=1 \
    "$ROOT/bin/uninstall-macos-open-with" >/dev/null
  [[ ! -e "$quoted_workflow" ]] || fail "uninstaller left an orphaned Quick Action"
fi

if project_error="$("$TOOL" project lab-api "$TEST_ROOT/project" 2>&1)"; then
  fail "expected project command to refuse overwriting existing files"
fi
grep -Fq 'see docs/projects-vscode.md for the block to add manually' <<< "$project_error"

if [[ "${CODEX_CONTEXTS_LIVE_TESTS:-0}" == "1" ]]; then
  printf 'Running opt-in Codex doctor checks; these may contact configured services.\n' >&2

  business_doctor="$(
    env CODEX_HOME="$CODEX_HOMES_ROOT/business" \
      "$LIVE_CODEX" --strict-config doctor --json 2>/dev/null || true
  )"
  jq -e '.checks["config.load"].status == "ok"' <<< "$business_doctor" >/dev/null ||
    fail "Codex strict config load failed for business"

  api_doctor="$(
    env CODEX_HOME="$CODEX_HOMES_ROOT/lab-api" LAB_API_KEY=test-secret \
      "$LIVE_CODEX" --strict-config doctor --json 2>/dev/null || true
  )"
  jq -e '.checks["config.load"].status == "ok"' <<< "$api_doctor" >/dev/null ||
    fail "Codex strict config load failed for lab-api"

  azure_doctor="$(
    env CODEX_HOME="$CODEX_HOMES_ROOT/azure-lab" AZURE_LAB_API_KEY=test-secret \
      "$LIVE_CODEX" --strict-config doctor --json 2>/dev/null || true
  )"
  jq -e '.checks["config.load"].status == "ok"' <<< "$azure_doctor" >/dev/null ||
    fail "Codex strict config load failed for azure-lab"
fi

printf 'All tests passed.\n'
