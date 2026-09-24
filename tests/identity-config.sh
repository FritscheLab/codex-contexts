#!/usr/bin/env bash
# Offline regressions for configuration reads and failed model requests.
set -euo pipefail
CONFIG_TEST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$CONFIG_TEST_REPO/tests/common.sh"
CONFIG_TEST_TOOL="$(resolve_codex_home_tool "$CONFIG_TEST_REPO/bin")"
CONFIG_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-config-test.XXXXXX")"
trap 'rm -rf -- "$CONFIG_TEST_ROOT"' EXIT
export CODEX_HOMES_ROOT="$CONFIG_TEST_ROOT/identities"
export CODEX_UMGPT_MODELS_FILE="$CONFIG_TEST_ROOT/defaults.toml"
source "$CONFIG_TEST_TOOL"

fail() { printf 'Identity config test failure: %s\n' "$*" >&2; exit 1; }
expect_failure() {
  local diagnostic="$1"
  shift
  if ( "$@" ) >"$CONFIG_TEST_ROOT/output" 2>"$CONFIG_TEST_ROOT/error"; then
    fail "accepted failure: $diagnostic"
  fi
  grep -Fq -- "$diagnostic" "$CONFIG_TEST_ROOT/error" || {
    cat "$CONFIG_TEST_ROOT/error" >&2
    fail "missing diagnostic: $diagnostic"
  }
  [[ ! -s "$CONFIG_TEST_ROOT/output" ]] || fail 'failure printed normal output'
}

# Invalid defaults must fail before reporting success or creating an identity.
printf 'invalid defaults\n' >"$CODEX_UMGPT_MODELS_FILE"
expect_failure 'unsupported line 1' "$CONFIG_TEST_TOOL" umgpt-defaults
expect_failure 'unsupported line 1' "$CONFIG_TEST_TOOL" create-umgpt gpt-test
expect_failure 'unsupported line 1' "$CONFIG_TEST_TOOL" create-umgpt-low other-test
[[ ! -e "$CODEX_HOMES_ROOT/umgpt" && ! -e "$CODEX_HOMES_ROOT/umgpt-low" ]] ||
  fail 'invalid defaults left a partial identity'
(
  UMGPT_REPOSITORY_MODELS_FILE="$CODEX_UMGPT_MODELS_FILE"
  expect_failure 'unsupported line 1' umgpt_repository_default_model openai-only
  UMGPT_MODELS_FILE="$CONFIG_TEST_ROOT/absent-defaults.toml"
  expect_failure 'unsupported line 1' umgpt_default_model openai-only
  [[ ! -e "$UMGPT_MODELS_FILE" ]] || fail 'invalid repository defaults created local defaults'
  [[ "$(wc -l <"$CONFIG_TEST_ROOT/error" | tr -d '[:space:]')" == 1 ]] ||
    fail 'initialization failure produced a misleading secondary error'
)

# Large valid configs keep their first model; consuming only one line must not
# make the upstream reader fail with SIGPIPE under pipefail.
"$CONFIG_TEST_TOOL" create-api config-test https://provider.example.test/v1 \
  top-level-model CONFIG_TEST_KEY >/dev/null
for (( index=0; index<3000; index++ )); do
  printf '\n[profiles.profile_%s]\nmodel = "profile-model-%s"\n' "$index" "$index"
done >>"$CODEX_HOMES_ROOT/config-test/config.toml"
"$CONFIG_TEST_TOOL" show config-test >"$CONFIG_TEST_ROOT/output"
grep -Fq 'Model          : top-level-model' "$CONFIG_TEST_ROOT/output" ||
  fail 'large config lost its top-level model'

# A rejected URL or key must never invoke curl, even from a conditional caller.
curl() {
  : >"$CONFIG_TEST_ROOT/curl-called"
  cat >"$CONFIG_TEST_ROOT/curl-config"
  printf '%s\n' '{"data":[{"id":"model-a"}]}'
}
for invalid_value in $'first\nsecond' $'first\rsecond'; do
  expect_failure 'must fit on one line' fetch_model_ids \
    https://provider.example.test/v1 "$invalid_value"
  expect_failure 'must fit on one line' fetch_model_ids "$invalid_value" synthetic-key
done
[[ ! -e "$CONFIG_TEST_ROOT/curl-called" ]] || fail 'invalid input reached curl'
[[ "$(fetch_model_ids https://provider.example.test/v1 synthetic-key)" == model-a ]] ||
  fail 'valid model request failed'
grep -Fxq 'header = "Authorization: Bearer synthetic-key"' "$CONFIG_TEST_ROOT/curl-config" ||
  fail 'valid authorization header changed'
printf 'Identity config tests passed.\n'
