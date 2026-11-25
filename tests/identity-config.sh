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

# A valid quoted root key is the saved model, regardless of any profile model.
config="$CODEX_HOMES_ROOT/config-test/config.toml"
sed 's/^model = /"model" = /' "$config" >"$CONFIG_TEST_ROOT/quoted.toml"
mv "$CONFIG_TEST_ROOT/quoted.toml" "$config"
"$CONFIG_TEST_TOOL" show config-test >"$CONFIG_TEST_ROOT/output"
grep -Fq 'Model          : top-level-model' "$CONFIG_TEST_ROOT/output" ||
  fail 'show reported a profile model instead of the quoted root model'

(
  cd "$CONFIG_TEST_ROOT"
  export CODEX_HOMES_ROOT=relative-homes
  expect_failure 'CODEX_HOMES_ROOT must be an absolute path' "$CONFIG_TEST_TOOL" create-subscription ignored
  [[ ! -e relative-homes ]] || fail 'relative identity root left files'
)

# Hold both creates at the first attempt to claim the leaf directory. Exactly
# one may report success, and its configuration must be the one that survives.
python3 -I - "$CONFIG_TEST_TOOL" "$CONFIG_TEST_ROOT" <<'PY'
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tomllib

tool, root = Path(sys.argv[1]), Path(sys.argv[2])
shim_dir = root / 'claim-bin'
shim_dir.mkdir()
mkdir = shim_dir / 'mkdir'
mkdir.write_text('''#!/usr/bin/env python3
import os
from pathlib import Path
import sys
import time

if sys.argv[-1] == os.environ['CLAIM_TEST_HOME']:
    barrier = Path(os.environ['CLAIM_TEST_BARRIER'])
    (barrier / str(os.getpid())).touch()
    deadline = time.monotonic() + 5
    while len(list(barrier.iterdir())) < 2:
        if time.monotonic() > deadline:
            raise SystemExit('second create did not reach the claim')
        time.sleep(0.02)
real = os.environ['CLAIM_TEST_MKDIR']
os.execv(real, [real, *sys.argv[1:]])
''')
mkdir.chmod(0o700)
base_env = dict(os.environ, PATH=f'{shim_dir}{os.pathsep}{os.environ["PATH"]}',
                CLAIM_TEST_MKDIR=shutil.which('mkdir'))
for identity, field, choices, arguments in (
    ('claim-subscription', 'cli_auth_credentials_store', ('file', 'keyring'),
     lambda value: ('create-subscription', 'claim-subscription', value)),
    ('claim-api', 'model', ('model-a', 'model-b'),
     lambda value: ('create-api', 'claim-api', 'https://provider.example.test/v1', value, 'CONFIG_TEST_KEY')),
):
    barrier = root / identity
    barrier.mkdir()
    home = Path(os.environ['CODEX_HOMES_ROOT']) / identity
    environment = dict(base_env, CLAIM_TEST_HOME=str(home), CLAIM_TEST_BARRIER=str(barrier))
    processes = [subprocess.Popen([tool, *arguments(choice)], env=environment, text=True,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE) for choice in choices]
    results = [process.communicate(timeout=10) for process in processes]
    winners = [choice for choice, process in zip(choices, processes) if process.returncode == 0]
    assert len(winners) == 1, results
    configs = tomllib.loads((home / 'config.toml').read_text())
    assert configs[field] == winners[0], (configs, results)
    for process, (_, error) in zip(processes, results):
        if process.returncode != 0:
            assert 'refusing to overwrite existing path' in error, results
PY

# A failed publication releases the new home so users can retry under its name.
mkdir -p "$CONFIG_TEST_ROOT/failed-publication"
printf '%s\n' '#!/bin/sh' 'echo "fixture publication failure" >&2' 'exit 1' >"$CONFIG_TEST_ROOT/failed-publication/mv"
chmod +x "$CONFIG_TEST_ROOT/failed-publication/mv"
( export PATH="$CONFIG_TEST_ROOT/failed-publication:$PATH"
  expect_failure 'fixture publication failure' "$CONFIG_TEST_TOOL" create-subscription publication-test
)
[[ ! -e "$CODEX_HOMES_ROOT/publication-test" ]] || fail 'failed publication left an incomplete home'
"$CONFIG_TEST_TOOL" create-subscription publication-test >/dev/null

# A rejected URL or key must never invoke curl, even from a conditional caller.
mkdir -p "$CONFIG_TEST_ROOT/bin"
export CONFIG_TEST_CURL_ROOT="$CONFIG_TEST_ROOT"
export CODEX_CONTEXTS_ENV_ALLOW="$CODEX_CONTEXTS_ENV_ALLOW CONFIG_TEST_CURL_ROOT"
cat >"$CONFIG_TEST_ROOT/bin/curl" <<'EOF'
#!/usr/bin/env bash
  : >"$CONFIG_TEST_CURL_ROOT/curl-called"
  cat >"$CONFIG_TEST_CURL_ROOT/curl-config"
  printf '%s\n' '{"data":[{"id":"model-a"}]}'
EOF
chmod +x "$CONFIG_TEST_ROOT/bin/curl"
export PATH="$CONFIG_TEST_ROOT/bin:$PATH"
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
