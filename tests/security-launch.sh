#!/usr/bin/env bash
# Offline security regressions: synthetic keys, temporary homes, no provider calls.
set -euo pipefail

SECURITY_TEST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$SECURITY_TEST_REPO/tests/common.sh"
SECURITY_TEST_TOOL="$(resolve_codex_home_tool "$SECURITY_TEST_REPO/bin")"
SECURITY_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-security-test.XXXXXX")"
trap 'rm -rf -- "$SECURITY_TEST_ROOT"' EXIT
export CODEX_HOMES_ROOT="$SECURITY_TEST_ROOT/homes"
export CODEX_UMGPT_MODELS_FILE="$SECURITY_TEST_ROOT/models.toml"
export DIRENV_CONFIG="$SECURITY_TEST_ROOT/direnv-config"
export XDG_DATA_HOME="$SECURITY_TEST_ROOT/xdg-data"
export CODEX_CONTEXTS_ENV_ALLOW=CODEX_SECURITY_TEST_OUTPUT
export CODEX_SECURITY_TEST_OUTPUT="$SECURITY_TEST_ROOT/environment.json"
unset CODEX_HOME CODEX_IDENTITY DIRENV_DIFF DIRENV_DIR DIRENV_FILE DIRENV_WATCHES
source "$SECURITY_TEST_TOOL"

fail() { printf 'Security launch test failure: %s\n' "$*" >&2; exit 1; }
reject() {
  local diagnostic="$1"
  shift
  rm -f "$CODEX_SECURITY_TEST_OUTPUT"
  if "$@" >"$SECURITY_TEST_ROOT/output" 2>"$SECURITY_TEST_ROOT/error"; then
    fail "accepted rejected input: $diagnostic"
  fi
  grep -Fq -- "$diagnostic" "$SECURITY_TEST_ROOT/error" || {
    cat "$SECURITY_TEST_ROOT/error" >&2
    fail "missing diagnostic: $diagnostic"
  }
  [[ ! -e "$CODEX_SECURITY_TEST_OUTPUT" ]] || fail 'rejected input reached a launched program'
}

mkdir -p "$SECURITY_TEST_ROOT/bin"
cat >"$SECURITY_TEST_ROOT/bin/codex" <<'EOF'
#!/usr/bin/env python3
import json, os, sys
with open(os.environ["CODEX_SECURITY_TEST_OUTPUT"], "w") as handle:
    json.dump({"environment": dict(os.environ), "args": sys.argv[1:], "pid": os.getpid()}, handle)
EOF
cat >"$SECURITY_TEST_ROOT/bin/curl" <<'EOF'
#!/usr/bin/env python3
import json, os, sys
with open(os.environ["CODEX_SECURITY_TEST_OUTPUT"], "w") as handle:
    json.dump({"environment": dict(os.environ), "args": sys.argv[1:], "config": sys.stdin.read()}, handle)
print('{"data":[{"id":"synthetic-model"}]}')
EOF
chmod +x "$SECURITY_TEST_ROOT/bin/codex"
chmod +x "$SECURITY_TEST_ROOT/bin/curl"
export PATH="$SECURITY_TEST_ROOT/bin:$PATH"

# Reject remote cleartext and authority tricks before storing or sending keys.
for base in http://provider.example.test/v1 http://localhost.evil.test/v1 \
  http://127.0.0.1.evil.test/v1 http://localhost@evil.test/v1 \
  'http://[::1]@evil.test/v1' http://localhost:99999/v1 \
  'https://provider.example.test/v1?query=secret' 'https://provider.example.test/#fragment'; do
  reject '' "$SECURITY_TEST_TOOL" create-api insecure "$base" model-a SECURITY_API_KEY
  [[ ! -e "$CODEX_HOMES_ROOT/insecure" ]] || fail 'rejected endpoint created an identity'
done
for base in https://provider.example.test/v1 http://localhost:8080/v1 \
  http://127.0.0.1/v1 'http://[::1]:8080/v1'; do
  data_helper url "$base"
done
for key in PATH HOME BASH_ENV PYTHONPATH NODE_OPTIONS LD_PRELOAD DYLD_INSERT_LIBRARIES CODEX_HOME; do
  reject 'runtime or launcher variable' "$SECURITY_TEST_TOOL" create-api reserved \
    https://provider.example.test/v1 model-a "$key"
done
curl() { fail 'invalid endpoint reached curl'; }
reject 'remote providers require HTTPS' fetch_model_ids http://provider.example.test/v1 synthetic-key

"$SECURITY_TEST_TOOL" create-api secure https://provider.example.test/v1 model-a SECURITY_API_KEY >/dev/null
"$SECURITY_TEST_TOOL" create-subscription subscription >/dev/null
secure_home="$CODEX_HOMES_ROOT/secure"
cp "$secure_home/config.toml" "$SECURITY_TEST_ROOT/provider-config"
sed 's#https://provider.example.test#http://provider.example.test#' \
  "$SECURITY_TEST_ROOT/provider-config" >"$secure_home/config.toml"
reject 'remote providers require HTTPS' "$SECURITY_TEST_TOOL" run secure --version
cp "$SECURITY_TEST_ROOT/provider-config" "$secure_home/config.toml"
printf 'SECURITY_API_KEY="stored-key"\n' >"$secure_home/api-key.env"
export SECURITY_API_KEY=inherited-other-identity
export AWS_SECRET_ACCESS_KEY=unrelated-cloud-secret
export GITHUB_TOKEN=unrelated-source-secret
export OPENAI_API_KEY=unrelated-model-secret
export SSH_AUTH_SOCK=/unrelated/credential-agent
"$SECURITY_TEST_TOOL" run secure --version >/dev/null 2>&1
python3 -I - "$CODEX_SECURITY_TEST_OUTPUT" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
env = data["environment"]
assert "SECURITY_API_KEY" not in env
assert env["CODEX_HOMES_ROOT"].endswith("/homes")
assert data["args"] == ["--version"]
assert all(key not in env for key in ("AWS_SECRET_ACCESS_KEY", "GITHUB_TOKEN", "OPENAI_API_KEY", "SSH_AUTH_SOCK"))
PY

# Model discovery must use the selected provider table, rather than the first
# base_url in a file containing several providers, and keep client env clean.
cp "$secure_home/api-key.env" "$secure_home/.env"
cat >"$secure_home/config.toml" <<'EOF'
model = "model-a"
model_provider = "secure"
[model_providers.decoy]
base_url = "https://decoy.example.test/v1"
env_key = "DECOY_API_KEY"
[model_providers.secure]
base_url = "https://selected.example.test/v1"
env_key = "SECURITY_API_KEY"
EOF
"$SECURITY_TEST_TOOL" models secure >/dev/null 2>&1
python3 -I - "$CODEX_SECURITY_TEST_OUTPUT" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["args"][0] == "-q"
assert 'url = "https://selected.example.test/v1/models"' in data["config"]
assert "stored-key" not in " ".join(data["args"])
assert all(key not in data["environment"] for key in ("AWS_SECRET_ACCESS_KEY", "GITHUB_TOKEN", "SECURITY_API_KEY"))
PY
cp "$SECURITY_TEST_ROOT/provider-config" "$secure_home/config.toml"
rm "$secure_home/.env"
"$SECURITY_TEST_TOOL" run subscription --version >/dev/null 2>&1
python3 -I - "$CODEX_SECURITY_TEST_OUTPUT" <<'PY'
import json, sys
env = json.load(open(sys.argv[1]))["environment"]
assert "SECURITY_API_KEY" not in env
PY

# Noninteractive launches replace the wrapper process, preserving cancellation
# by PID rather than leaving a second Bash process above the coding agent.
"$SECURITY_TEST_TOOL" run subscription --version >/dev/null 2>&1 &
launcher_pid=$!
wait "$launcher_pid"
python3 -I - "$CODEX_SECURITY_TEST_OUTPUT" "$launcher_pid" <<'PY'
import json, sys
assert json.load(open(sys.argv[1]))["pid"] == int(sys.argv[2])
PY

# Explicit legacy env_key configurations retain external selected-key support.
python3 -I - "$secure_home/config.toml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text('\n'.join('env_key = "SECURITY_API_KEY"' if line.startswith('auth = ') else line
                          for line in path.read_text().splitlines()) + '\n')
PY
mv "$secure_home/api-key.env" "$SECURITY_TEST_ROOT/stored-env"
reject 'missing selected key SECURITY_API_KEY' "$SECURITY_TEST_TOOL" run secure
CODEX_CONTEXTS_ENV_ALLOW='CODEX_SECURITY_TEST_OUTPUT SECURITY_API_KEY' \
  "$SECURITY_TEST_TOOL" run secure --version >/dev/null 2>&1
python3 -I - "$CODEX_SECURITY_TEST_OUTPUT" <<'PY'
import json, sys
assert json.load(open(sys.argv[1]))["environment"]["SECURITY_API_KEY"] == "inherited-other-identity"
PY
mv "$SECURITY_TEST_ROOT/stored-env" "$secure_home/api-key.env"
cp "$SECURITY_TEST_ROOT/provider-config" "$secure_home/config.toml"
reject 'unsafe CODEX_CONTEXTS_ENV_ALLOW variable' env CODEX_CONTEXTS_ENV_ALLOW='BASH_ENV' \
  "$SECURITY_TEST_TOOL" run secure

# Generic identities may redirect providers over HTTPS, but known endpoint
# overrides in project layers, selected profiles, or CLI flags stay encrypted.
reject 'remote providers require HTTPS' "$SECURITY_TEST_TOOL" run secure \
  -c 'model_providers.secure.base_url=http://remote.example.test/v1'
reject 'remote providers require HTTPS' "$SECURITY_TEST_TOOL" run secure \
  -c '"model_providers"."secure"."base\u005furl"="http://remote.example.test/v1"'
"$SECURITY_TEST_TOOL" run secure -c 'model_providers.secure.base_url=https://other.example.test/v1' >/dev/null 2>&1
generic_project="$SECURITY_TEST_ROOT/generic-project"
mkdir -p "$generic_project/.codex" "$generic_project/child"
printf 'model_providers.secure.base_url = "http://remote.example.test/v1"\n' >"$generic_project/.codex/config.toml"
reject 'remote providers require HTTPS' "$SECURITY_TEST_TOOL" run secure --cd="$generic_project/child"
"$SECURITY_TEST_TOOL" project secure "$generic_project" >/dev/null
direnv allow "$generic_project" >/dev/null 2>&1
reject 'remote providers require HTTPS' env CODEX_VSCODE_CLI="$SECURITY_TEST_ROOT/bin/codex" \
  CODEX_VSCODE_DOCK_LABEL=0 CODEX_MACOS_SKIP_REGISTER=1 \
  "$SECURITY_TEST_TOOL" vscode secure "$generic_project"
printf 'model_providers.secure.base_url = "https://other.example.test/v1"\n' >"$generic_project/.codex/config.toml"
"$SECURITY_TEST_TOOL" run secure -C "$generic_project/child" >/dev/null 2>&1
printf 'openai_base_url = "http://remote.example.test/v1"\n' >"$secure_home/test-profile.config.toml"
reject 'remote providers require HTTPS' "$SECURITY_TEST_TOOL" run secure --profile test-profile

# Every recognized endpoint is checked in saved settings, discovery commands,
# CLI overrides, external/inline profiles, and ancestor project settings.
# Keep these fixtures independent of the generated config's table order.
write_endpoint_config() {
  local file="$1" endpoint="$2" value="$3"
  {
    printf '%s\n' 'model = "model-a"' 'model_provider = "secure"' \
      "model_providers.secure.auth = $(data_helper auth-config "$secure_home" SECURITY_API_KEY)"
    if [[ "$endpoint" != model_providers.secure.base_url ]]; then
      printf '%s\n' 'model_providers.secure.base_url = "https://provider.example.test/v1"'
    fi
    printf '%s = %s\n' "$endpoint" "$value"
  } >"$file"
}
for endpoint in openai_base_url chatgpt_base_url \
  model_providers.secure.base_url model_providers.secure.model_catalog_url; do
  write_endpoint_config "$secure_home/config.toml" "$endpoint" '"http://remote.example.test/endpoint"'
  reject 'remote providers require HTTPS' "$SECURITY_TEST_TOOL" run secure
  reject 'remote providers require HTTPS' "$SECURITY_TEST_TOOL" models secure
  cp "$SECURITY_TEST_ROOT/provider-config" "$secure_home/config.toml"
  reject 'remote providers require HTTPS' "$SECURITY_TEST_TOOL" run secure \
    -c "$endpoint=http://remote.example.test/endpoint"
  reject 'remote providers require HTTPS' "$SECURITY_TEST_TOOL" run secure \
    --config="$endpoint=\"http://remote.example.test/endpoint\""

  printf '%s = "http://remote.example.test/endpoint"\n' "$endpoint" >"$secure_home/endpoint-profile.config.toml"
  reject 'remote providers require HTTPS' "$SECURITY_TEST_TOOL" run secure -p endpoint-profile
  printf '\n[profiles.inline_endpoint]\n%s = "http://remote.example.test/endpoint"\n' "$endpoint" \
    >>"$secure_home/config.toml"
  reject 'remote providers require HTTPS' "$SECURITY_TEST_TOOL" run secure --profile inline_endpoint
  cp "$SECURITY_TEST_ROOT/provider-config" "$secure_home/config.toml"
  printf '%s = "http://remote.example.test/endpoint"\n' "$endpoint" >"$generic_project/.codex/config.toml"
  reject 'remote providers require HTTPS' "$SECURITY_TEST_TOOL" run secure -C "$generic_project/child"

  for url in https://provider.example.test/endpoint http://localhost:8080/endpoint \
    http://127.0.0.1/endpoint 'http://[::1]:8080/endpoint'; do
    write_endpoint_config "$secure_home/config.toml" "$endpoint" "\"$url\""
    "$SECURITY_TEST_TOOL" run secure --version >/dev/null 2>&1
  done
  for value in '""' false 17 '[]' '{ nested = "https://provider.example.test/endpoint" }'; do
    write_endpoint_config "$secure_home/config.toml" "$endpoint" "$value"
    reject 'URL must be a nonempty string' "$SECURITY_TEST_TOOL" run secure
    cp "$SECURITY_TEST_ROOT/provider-config" "$secure_home/config.toml"
    reject 'URL must be a nonempty string' "$SECURITY_TEST_TOOL" run secure -c "$endpoint=$value"
  done
  if [[ "$endpoint" != model_providers.secure.model_catalog_url ]]; then
    reject 'query' "$SECURITY_TEST_TOOL" run secure \
      -c "$endpoint=https://provider.example.test/endpoint?version=1"
  fi
done
cp "$SECURITY_TEST_ROOT/provider-config" "$secure_home/config.toml"
printf 'model_providers.secure.model_catalog_url = "http://remote.example.test/models"\n' \
  >"$generic_project/.codex/config.toml"
reject 'remote providers require HTTPS' env CODEX_VSCODE_CLI="$SECURITY_TEST_ROOT/bin/codex" \
  CODEX_VSCODE_DOCK_LABEL=0 CODEX_MACOS_SKIP_REGISTER=1 \
  "$SECURITY_TEST_TOOL" vscode secure "$generic_project"
: >"$generic_project/.codex/config.toml"
reject 'remote providers require HTTPS' "$SECURITY_TEST_TOOL" run secure \
  -c '"model_providers"."secure"."model_catalog\u005furl"="http://remote.example.test/models"'
reject 'fragment' "$SECURITY_TEST_TOOL" run secure \
  -c 'model_providers.secure.model_catalog_url="https://provider.example.test/models#fragment"'
reject 'model_catalog_url' "$SECURITY_TEST_TOOL" run secure \
  -c 'model_providers.secure.model_catalog_url="https://user:credential-sentinel@catalog.example.test/models?key=query-sentinel"'
if grep -Eq 'credential-sentinel|query-sentinel' "$SECURITY_TEST_ROOT/error"; then
  fail 'endpoint rejection printed credentials or query parameters'
fi
for endpoint_table in 'model_providers = false' 'model_providers.other = []' \
  'profiles = false' 'profiles.other = []'; do
  reject 'must be a TOML table' "$SECURITY_TEST_TOOL" run secure -c "$endpoint_table"
done

# Catalog URLs identify the complete request, including legitimate query
# parameters; base URLs keep their existing no-query contract.
catalog_url='https://provider.example.test/catalog/models?api-version=2026-01-01&scope=text'
write_endpoint_config "$secure_home/config.toml" model_providers.secure.model_catalog_url "\"$catalog_url\""
"$SECURITY_TEST_TOOL" run secure --version >/dev/null 2>&1
cp "$SECURITY_TEST_ROOT/provider-config" "$secure_home/config.toml"
"$SECURITY_TEST_TOOL" run secure -c "model_providers.secure.model_catalog_url=$catalog_url" >/dev/null 2>&1
"$SECURITY_TEST_TOOL" run secure -c "model_providers.secure.model_catalog_url=\"$catalog_url\"" >/dev/null 2>&1

# A credential file is data: expressions and additional assignments never run.
printf 'SECURITY_API_KEY="$(touch %s)"\n' "$SECURITY_TEST_ROOT/credential-executed" >"$secure_home/api-key.env"
reject 'data, not shell expressions' "$SECURITY_TEST_TOOL" run secure
[[ ! -e "$SECURITY_TEST_ROOT/credential-executed" ]] || fail '.env executed shell code'
printf 'SECURITY_API_KEY=synthetic-key\nBASH_ENV=/untrusted/script\n' >"$secure_home/api-key.env"
reject 'must contain only SECURITY_API_KEY' "$SECURITY_TEST_TOOL" run secure
printf 'SECURITY_API_KEY="%s"\n' 'literal\$dollar\`tick\"quote\\slash' >"$secure_home/api-key.env"
"$SECURITY_TEST_TOOL" run secure >/dev/null 2>&1
[[ "$(data_helper secret "$secure_home")" == 'literal$dollar`tick"quote\slash' ]] || fail 'literal key decoding changed'
mv "$secure_home/api-key.env" "$SECURITY_TEST_ROOT/credential-target"
ln -s "$SECURITY_TEST_ROOT/credential-target" "$secure_home/api-key.env"
reject 'symlinked or nonregular credential' "$SECURITY_TEST_TOOL" set-key secure
reject 'symlinked or nonregular credential' "$SECURITY_TEST_TOOL" run secure
[[ -L "$secure_home/api-key.env" ]] || fail 'credential update replaced an unapproved symlink'

# Parsed TOML must catch provider redirection regardless of key spelling, in
# the actual -C directory and its ancestors, before either CLI or IDE launches.
"$SECURITY_TEST_TOOL" create-umgpt gpt-security-test scoped >/dev/null
"$SECURITY_TEST_TOOL" create-umgpt-low gpt-security-test scoped-low >/dev/null
printf 'UMGPT_API_KEY=synthetic-key\n' >"$CODEX_HOMES_ROOT/scoped/api-key.env"
for scoped_identity in scoped scoped-low; do
  cp "$CODEX_HOMES_ROOT/$scoped_identity/config.toml" "$SECURITY_TEST_ROOT/$scoped_identity-config"
  cat >"$CODEX_HOMES_ROOT/$scoped_identity/config.toml" <<EOF
model = "gpt-security-test"
model_provider = "$scoped_identity"
[model_providers.$scoped_identity]
base_url = "https://api.toolkit.umgpt.umich.edu/v1"
env_key = "UMGPT_API_KEY"
model_catalog_url = "https://other.example.test/models?version=1"
EOF
  reject 'may not override its model catalog URL' "$SECURITY_TEST_TOOL" run "$scoped_identity"
  cp "$SECURITY_TEST_ROOT/$scoped_identity-config" "$CODEX_HOMES_ROOT/$scoped_identity/config.toml"
done
reject 'can bypass' "$SECURITY_TEST_TOOL" run scoped \
  -c 'model_providers.scoped.model_catalog_url="https://other.example.test/models?key=query-sentinel"'
if grep -Fq 'query-sentinel' "$SECURITY_TEST_ROOT/error"; then
  fail 'scope rejection printed catalog query parameters'
fi
reject 'can bypass' "$SECURITY_TEST_TOOL" run scoped \
  -c 'chatgpt_base_url="https://other.example.test/"'
project="$SECURITY_TEST_ROOT/project"
mkdir -p "$project/.codex" "$project/child"
for config in 'model_provider = "other"' \
  '"model\u005fprovider" = "other"' \
  'chatgpt_base_url = "https://other.example.test/"' \
  'model_providers.scoped.base_url = "https://other.example.test/v1"' \
  'model_providers = { scoped = { base_url = "https://other.example.test/v1" } }'; do
  printf '%s\n' "$config" >"$project/.codex/config.toml"
  reject 'may not override the provider' "$SECURITY_TEST_TOOL" run scoped -C "$project/child"
done
printf 'model = "gpt-allowed"\n' >"$project/.codex/config.toml"
"$SECURITY_TEST_TOOL" run scoped --cd="$project/child" --version >/dev/null 2>&1
reject 'can bypass' "$SECURITY_TEST_TOOL" run scoped -c '"model\u005fprovider"="other"'
printf 'model_providers.scoped.base_url = "https://other.example.test/v1"\n' >"$project/.codex/config.toml"
reject 'may not override the provider' validate_project_umgpt_model scoped "$project/child"

# The exact generated context is reviewed and approved as a unit. Any later
# edit to either file invalidates the receipt and must leave direnv blocked.
approval_project="$SECURITY_TEST_ROOT/approval-project"
mkdir -p "$approval_project"
"$SECURITY_TEST_TOOL" project subscription "$approval_project" >/dev/null
receipt="$("$SECURITY_TEST_TOOL" project-fingerprint "$approval_project")"
cp "$approval_project/.envrc" "$SECURITY_TEST_ROOT/approval-envrc"
"$SECURITY_TEST_TOOL" project-approve "$approval_project" "$receipt" >/dev/null 2>&1
direnv deny "$approval_project" >/dev/null 2>&1
printf '\n# changed after review\n' >>"$approval_project/.envrc"
reject '' "$SECURITY_TEST_TOOL" project-approve "$approval_project" "$receipt"
if direnv exec "$approval_project" true >/dev/null 2>&1; then
  fail 'changed context retained approval'
fi
cp "$SECURITY_TEST_ROOT/approval-envrc" "$approval_project/.envrc"
approval_workspace="$approval_project/.vscode/approval-project.code-workspace"
cp "$approval_workspace" "$SECURITY_TEST_ROOT/approval-workspace"
printf '\n// changed after review\n' >>"$approval_workspace"
reject '' "$SECURITY_TEST_TOOL" project-approve "$approval_project" "$receipt"
cp "$SECURITY_TEST_ROOT/approval-workspace" "$approval_workspace"

# A mutation inside `direnv allow` must be detected and its approval revoked.
mkdir -p "$SECURITY_TEST_ROOT/approval-bin"
export CODEX_SECURITY_REAL_DIRENV="$(command -v direnv)"
cat >"$SECURITY_TEST_ROOT/approval-bin/direnv" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == allow ]]; then
  printf '\n# changed during approval\n' >>"$2/.envrc"
fi
exec "$CODEX_SECURITY_REAL_DIRENV" "$@"
EOF
chmod +x "$SECURITY_TEST_ROOT/approval-bin/direnv"
reject 'approval revoked' env PATH="$SECURITY_TEST_ROOT/approval-bin:$PATH" \
  "$SECURITY_TEST_TOOL" project-approve "$approval_project" "$receipt"
if direnv exec "$approval_project" true >/dev/null 2>&1; then
  fail 'context changed during approval retained a usable approval'
fi

printf 'Security launch tests passed.\n'
