#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

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
export DIRENV_LOG_FORMAT=""
export XDG_DATA_HOME="$TEST_ROOT/xdg-data"
export CODEX_HOMES_ROOT="$TEST_ROOT/codex-homes"
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

TOOL="$ROOT/bin/codex-home"

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

"$TOOL" create-umgpt um-model >/dev/null
assert_api_config \
  "$CODEX_HOMES_ROOT/umgpt/config.toml" \
  umgpt um-model https://api.toolkit.umgpt.umich.edu/v1 UMGPT_API_KEY

mkdir -p "$TEST_ROOT/shared-skills/skill-two"
printf '%s\n' '# Skill two' > "$TEST_ROOT/shared-skills/skill-two/SKILL.md"
"$TOOL" share-skills-all "$TEST_ROOT/shared-skills" >/dev/null 2>&1
[[ -L "$CODEX_HOMES_ROOT/lab-api/skills/skill-two" ]]
[[ -L "$CODEX_HOMES_ROOT/azure-lab/skills/skill-two" ]]
[[ -L "$CODEX_HOMES_ROOT/umgpt/skills/skill-two" ]]

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
  'printf "%s\n" "{\"data\":[{\"id\":\"model-a\"},{\"id\":\"model-b\"}]}"' \
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
# Older direnv versions report an error when denying an unapproved .envrc.
CODEX_TEST_DIRENV_DENY_ERROR=missing \
  CODEX_TEST_REAL_DIRENV="$(command -v direnv)" \
  PATH="$TEST_ROOT/direnv-deny-bin:$PATH" \
  "$TOOL" project-change pro "$TEST_ROOT/legacy-project" >/dev/null
grep -q 'CODEX_IDENTITY="pro"' "$TEST_ROOT/legacy-project/.envrc" ||
  fail "project-change did not accept a legacy generated workspace"
[[ ! -e "$legacy_workspace" ]] ||
  fail "project-change did not remove the legacy workspace"
grep -Fq '"window.title": "legacy-project [CODEX: PRO]"' \
  "$TEST_ROOT/legacy-project/.vscode/legacy-project.code-workspace"
if grep -Fqx '/.vscode/codex-context.code-workspace' "$legacy_exclude"; then
  fail "project-change left the legacy workspace Git exclusion behind"
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

if [[ "$(uname -s)" == "Darwin" ]]; then
  CODEX_MACOS_APP_DIR="$TEST_ROOT/apps" \
    CODEX_MACOS_SKIP_REGISTER=1 \
    "$ROOT/bin/install-macos-open-with" >/dev/null 2>&1
  test_app="$TEST_ROOT/apps/Codex Project.app"
  [[ -x "$test_app/Contents/Resources/codex-home" ]]
  plutil -p "$test_app/Contents/Info.plist" | grep -q 'public.folder'
  osadecompile "$test_app/Contents/Resources/Scripts/main.scpt" \
    > "$TEST_ROOT/codex-project-app.applescript"
  grep -Fq 'list --names' "$TEST_ROOT/codex-project-app.applescript"
  grep -Fq 'Open with current Codex context' "$TEST_ROOT/codex-project-app.applescript"
  grep -Fq 'project-change' "$TEST_ROOT/codex-project-app.applescript"
  grep -Fq 'project-reset' "$TEST_ROOT/codex-project-app.applescript"
  grep -Fq 'project-review' "$TEST_ROOT/codex-project-app.applescript"
  grep -Fq 'Review in VS Code' "$TEST_ROOT/codex-project-app.applescript"
  grep -Fq 'Review Again' "$TEST_ROOT/codex-project-app.applescript"
  grep -Fq 'Approve & Open' "$TEST_ROOT/codex-project-app.applescript"

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
    CODEX_MACOS_SKIP_REGISTER=1 \
    "$ROOT/bin/install-macos-open-with" >/dev/null 2>&1
  [[ -x "$test_app/Contents/Resources/codex-home" ]]
  find "$TEST_ROOT/apps/.codex-project-backups" -maxdepth 1 -type d \
    -name '*.app.backup' -print -quit | grep -q . ||
    fail "reinstall did not retain a non-application backup"

  CODEX_MACOS_APP_DIR="$TEST_ROOT/apps" \
    CODEX_MACOS_TRASH_DIR="$TEST_ROOT/trash" \
    CODEX_MACOS_SKIP_REGISTER=1 \
    "$ROOT/bin/uninstall-macos-open-with" >/dev/null
  [[ ! -e "$test_app" ]]
  find "$TEST_ROOT/trash" -maxdepth 1 -type d -name 'Codex Project.*.app' \
    -print -quit | grep -q . || fail "uninstaller did not move the app to Trash"
  "$TOOL" project-reset "$TEST_ROOT/app-project" >/dev/null
  [[ ! -e "$TEST_ROOT/app-project/.envrc" ]] ||
    fail "repository helper did not reset a context created by the bundled helper"
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
