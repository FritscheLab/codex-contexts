#!/usr/bin/env bash
# Managed command-backed keys and conservative explicit migration, offline only.
set -euo pipefail
AUTH_TEST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$AUTH_TEST_REPO/tests/common.sh"
AUTH_TEST_TOOL="$(resolve_codex_home_tool "$AUTH_TEST_REPO/bin")"
AUTH_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-api-auth.XXXXXX")"
trap 'rm -rf -- "$AUTH_TEST_ROOT"' EXIT
export CODEX_HOMES_ROOT="$AUTH_TEST_ROOT/homes"
export CODEX_UMGPT_MODELS_FILE="$AUTH_TEST_ROOT/models.toml"
export AUTH_TEST_OUTPUT="$AUTH_TEST_ROOT/launched.json"
export CODEX_CONTEXTS_ENV_ALLOW='AUTH_TEST_OUTPUT AUTH_TEST_KEY'
source "$AUTH_TEST_TOOL"
fail() { printf 'API auth test failure: %s\n' "$*" >&2; exit 1; }
reject() {
  local diagnostic="$1"
  shift
  rm -f "$AUTH_TEST_OUTPUT"
  if ( "$@" ) >"$AUTH_TEST_ROOT/output" 2>"$AUTH_TEST_ROOT/error"; then
    fail "accepted rejected input: $diagnostic"
  fi
  grep -Fq -- "$diagnostic" "$AUTH_TEST_ROOT/error" || {
    cat "$AUTH_TEST_ROOT/error" >&2
    fail "missing diagnostic: $diagnostic"
  }
  [[ ! -e "$AUTH_TEST_OUTPUT" ]] || fail 'rejected key reached a launched program'
}
mkdir -p "$AUTH_TEST_ROOT/bin"
cat >"$AUTH_TEST_ROOT/bin/codex" <<'EOF'
#!/usr/bin/env python3
import json, os
with open(os.environ['AUTH_TEST_OUTPUT'], 'w') as output:
    json.dump(dict(os.environ), output)
EOF
chmod +x "$AUTH_TEST_ROOT/bin/codex"
export PATH="$AUTH_TEST_ROOT/bin:$PATH"

"$AUTH_TEST_TOOL" create-subscription portable >/dev/null
"$AUTH_TEST_TOOL" create-subscription protected keyring >/dev/null
reject 'file or keyring' "$AUTH_TEST_TOOL" create-subscription unsupported auto
[[ ! -e "$CODEX_HOMES_ROOT/unsupported" ]] || fail 'invalid store created an identity'
python3 -I - "$CODEX_HOMES_ROOT" <<'PY'
from pathlib import Path
import sys, tomllib
for name, store in [('portable', 'file'), ('protected', 'keyring')]:
    assert tomllib.loads((Path(sys.argv[1])/name/'config.toml').read_text())['cli_auth_credentials_store'] == store
PY

# Keep a stable interpreter alias in saved configuration instead of pinning its
# versioned target. Later launches may discover Python through another PATH.
mkdir -p "$AUTH_TEST_ROOT/python alias"
ln -s "$(command -v python3)" "$AUTH_TEST_ROOT/python alias/python3"
PATH="$AUTH_TEST_ROOT/python alias:$PATH" "$AUTH_TEST_TOOL" create-api interpreter \
  https://provider.example.test/v1 model-a AUTH_TEST_KEY >/dev/null
python3 -I - "$CODEX_HOMES_ROOT/interpreter/config.toml" "$AUTH_TEST_ROOT/python alias/python3" <<'PY'
from pathlib import Path
import os, sys, tomllib
provider = tomllib.loads(Path(sys.argv[1]).read_text())["model_providers"]["interpreter"]
assert provider["auth"]["command"] == os.path.abspath(sys.argv[2])
PY
[[ "$(data_helper key-name "$CODEX_HOMES_ROOT/interpreter")" == AUTH_TEST_KEY ]] ||
  fail 'managed authentication depended on the current interpreter path'

"$AUTH_TEST_TOOL" create-api managed https://provider.example.test/v1 model-a AUTH_TEST_KEY >/dev/null
managed="$CODEX_HOMES_ROOT/managed"
printf 'stored-key' | data_helper store-key "$managed" AUTH_TEST_KEY >"$AUTH_TEST_ROOT/key-path"
python3 -I - "$managed/api-key.env" "$AUTH_TEST_ROOT/key-path" <<'PY'
from pathlib import Path
import stat, sys
assert Path(Path(sys.argv[2]).read_text().strip()).resolve() == Path(sys.argv[1]).resolve()
assert stat.S_IMODE(Path(sys.argv[1]).stat().st_mode) == 0o600
PY
export AUTH_TEST_KEY=unrelated-inherited-key
python3 -I - "$managed" "$AUTH_TEST_REPO/libexec/codex_contexts.py" <<'PY'
from pathlib import Path
import subprocess, sys, tomllib
home = Path(sys.argv[1]).resolve()
provider = tomllib.loads((home/'config.toml').read_text())['model_providers']['managed']
assert 'env_key' not in provider
auth = provider['auth']
assert auth['args'] == ['-I', str(Path(sys.argv[2]).resolve()), 'credential', str(home), 'AUTH_TEST_KEY']
assert Path(auth['command']).is_absolute()
assert auth['refresh_interval_ms'] == 0
assert subprocess.check_output([auth['command'], *auth['args']], text=True) == 'stored-key'
PY
"$AUTH_TEST_TOOL" run managed --version >/dev/null 2>&1
python3 -I - "$AUTH_TEST_OUTPUT" <<'PY'
import json, sys
assert 'AUTH_TEST_KEY' not in json.load(open(sys.argv[1]))
PY
mv "$managed/api-key.env" "$AUTH_TEST_ROOT/key-file"
reject 'missing selected key AUTH_TEST_KEY' "$AUTH_TEST_TOOL" run managed
mv "$AUTH_TEST_ROOT/key-file" "$managed/api-key.env"
printf 'AUTH_TEST_KEY="$(touch never-executed)"\n' >"$managed/api-key.env"
reject 'data, not shell expressions' "$AUTH_TEST_TOOL" run managed
printf 'AUTH_TEST_KEY="stored-key"\n' >"$managed/api-key.env"

# Native Codex automatically exports CODEX_HOME/.env at startup. Even an older
# command-backed identity must explicitly move that file before it can launch.
mv "$managed/api-key.env" "$managed/.env"
reject 'Codex automatically exports' "$AUTH_TEST_TOOL" run managed
reject 'Codex automatically exports' "$AUTH_TEST_TOOL" set-key managed
migrate_api_auth managed >/dev/null
[[ ! -e "$managed/.env" && -f "$managed/api-key.env" ]] || fail 'managed legacy file was not moved'
cp "$managed/api-key.env" "$managed/.env"
reject 'conflicting credential files' migrate_api_auth managed
rm "$managed/.env"

# A generated legacy table remains supported until explicitly migrated. Root
# and unrelated native settings must survive the single credential-line change.
python3 -I - "$managed/config.toml" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
text='sandbox_mode = "read-only"\n# preserved root comment\n'+p.read_text()
text='\n'.join('env_key = "AUTH_TEST_KEY" # preserved key comment' if line.startswith('auth = ') else line for line in text.splitlines())+'\n'
text+='\n[profiles.careful]\nmodel_reasoning_effort = "low"\n[model_providers.other]\nbase_url = "https://other.example.test/v1"\n'
p.write_text(text)
PY
mv "$managed/api-key.env" "$managed/.env"
"$AUTH_TEST_TOOL" run managed --version >/dev/null 2>&1
python3 -I - "$AUTH_TEST_OUTPUT" <<'PY'
import json, sys
assert json.load(open(sys.argv[1]))['AUTH_TEST_KEY'] == 'stored-key'
PY
cp "$managed/config.toml" "$AUTH_TEST_ROOT/legacy-config"
mv "$managed/.env" "$AUTH_TEST_ROOT/key-file"
migrate_api_auth managed >/dev/null
[[ ! -e "$managed/api-key.env" ]] || fail 'migration created or read a credential file'
mv "$AUTH_TEST_ROOT/key-file" "$managed/api-key.env"
python3 -I - "$AUTH_TEST_ROOT/legacy-config" "$managed/config.toml" <<'PY'
from pathlib import Path
import sys, tomllib
before, after = [tomllib.loads(Path(path).read_text()) for path in sys.argv[1:]]
provider=before['model_providers']['managed']
del provider['env_key']
provider['auth']=after['model_providers']['managed']['auth']
assert before == after
assert '# preserved root comment' in Path(sys.argv[2]).read_text()
assert '# preserved key comment' in Path(sys.argv[2]).read_text()
PY
cp "$managed/config.toml" "$AUTH_TEST_ROOT/migrated-config"
migrate_api_auth managed >/dev/null
cmp -s "$managed/config.toml" "$AUTH_TEST_ROOT/migrated-config" || fail 'repeat migration changed settings'

# Publication failures and interruption must restore both original file inodes.
# A late foreign path is preserved, with original recovery files kept if needed.
python3 -I - "$AUTH_TEST_REPO/libexec/codex_contexts.py" "$AUTH_TEST_ROOT" "$AUTH_TEST_ROOT/legacy-config" <<'PY'
from pathlib import Path
from contextlib import redirect_stderr
import io, os, runpy, signal, stat, sys
module = runpy.run_path(sys.argv[1])
root, source = map(Path, sys.argv[2:])
real_link, real_replace = os.link, os.replace

def snapshot(path):
    info = path.stat()
    return info.st_dev, info.st_ino, stat.S_IMODE(info.st_mode), info.st_uid, path.read_bytes()

for mode in ('success', 'before-publish', 'after-publish', 'signal', 'late-destination', 'late-legacy'):
    home = root / ('transaction-' + mode)
    home.mkdir(mode=0o700)
    config, legacy, key = home/'config.toml', home/'.env', home/'api-key.env'
    config.write_bytes(source.read_bytes())
    config.chmod(0o640)
    legacy.write_text('AUTH_TEST_KEY="transaction-key"\n')
    legacy.chmod(0o600)
    config_before, key_before = snapshot(config), snapshot(legacy)

    def replace(start, destination):
        if Path(destination) == config:
            if mode == 'before-publish':
                raise OSError('injected publication failure')
            if mode == 'late-legacy':
                legacy.write_text('unrelated later file')
                raise OSError('injected conflicting restore')
            real_replace(start, destination)
            if mode == 'after-publish':
                raise OSError('injected failure after publication')
            if mode == 'signal':
                os.kill(os.getpid(), signal.SIGTERM)
            return
        real_replace(start, destination)

    def link(start, destination, **options):
        if mode == 'late-destination' and Path(destination) == key:
            key.write_text('unrelated destination')
        real_link(start, destination, **options)

    os.link, os.replace = link, replace
    failed = False
    diagnostics = io.StringIO()
    try:
        with redirect_stderr(diagnostics):
            module['migrate_api_auth'](str(home), 'managed', 'api-key')
    except OSError:
        failed = True
    finally:
        os.link, os.replace = real_link, real_replace
    assert failed == (mode != 'success'), mode
    recovery = list(home.glob('.api-auth-migration.*'))
    if mode == 'success':
        assert not legacy.exists() and snapshot(key) == key_before, mode
        assert not recovery, mode
    elif mode == 'late-legacy':
        assert 'originals preserved at' in diagnostics.getvalue(), mode
        assert legacy.read_text() == 'unrelated later file', mode
        assert snapshot(config) == config_before, mode
        assert len(recovery) == 1, mode
        assert snapshot(recovery[0]/'key.before') == key_before, mode
        assert snapshot(recovery[0]/'config.before') == config_before, mode
    else:
        assert snapshot(config) == config_before and snapshot(legacy) == key_before, mode
        if mode == 'late-destination':
            assert key.read_text() == 'unrelated destination', mode
        else:
            assert not key.exists(), mode
        assert not recovery, mode
PY

# The callback's selected home cannot silently point at another identity.
python3 -I - "$managed/config.toml" "$managed" "$CODEX_HOMES_ROOT/portable" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
p.write_text(p.read_text().replace(str(Path(sys.argv[2]).resolve()), str(Path(sys.argv[3]).resolve())))
PY
reject 'unrecognized managed credential command' "$AUTH_TEST_TOOL" run managed
cp "$AUTH_TEST_ROOT/migrated-config" "$managed/config.toml"

# Unrelated hand-configured native authentication is left to Codex, without
# guessing its key storage or imposing our callback argument contract.
python3 -I - "$managed/config.toml" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
p.write_text('\n'.join('auth = { command = "/usr/bin/false", args = ["one", "two", "credential"] }'
                      if line.startswith('auth = ') else line for line in p.read_text().splitlines())+'\n')
PY
"$AUTH_TEST_TOOL" run managed --version >/dev/null 2>&1
cp "$AUTH_TEST_ROOT/migrated-config" "$managed/config.toml"

for variant in custom-header custom-name inline-provider; do
  python3 -I - "$AUTH_TEST_ROOT/legacy-config" "$managed/config.toml" "$variant" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text()
if sys.argv[3]=='custom-header': text=text.replace('wire_api =', 'http_headers = { "X-Custom" = "value" }\nwire_api =', 1)
elif sys.argv[3]=='custom-name': text=text.replace('Codex identity: managed', 'Hand-managed provider')
else: text='model_provider = "managed"\nmodel_providers.managed = { name = "Codex identity: managed", base_url = "https://provider.example.test/v1", env_key = "AUTH_TEST_KEY", wire_api = "responses" }\n'
Path(sys.argv[2]).write_text(text)
PY
  cp "$managed/config.toml" "$AUTH_TEST_ROOT/refused-config"
  reject 'refusing to migrate' migrate_api_auth managed
  cmp -s "$managed/config.toml" "$AUTH_TEST_ROOT/refused-config" || fail 'refused migration changed settings'
done
cp "$AUTH_TEST_ROOT/migrated-config" "$managed/config.toml"
mv "$managed/config.toml" "$AUTH_TEST_ROOT/symlink-target"
ln -s "$AUTH_TEST_ROOT/symlink-target" "$managed/config.toml"
reject 'symlinked or nonregular config' migrate_api_auth managed
[[ -L "$managed/config.toml" ]] || fail 'migration replaced a config symlink'
cmp -s "$AUTH_TEST_ROOT/symlink-target" "$AUTH_TEST_ROOT/migrated-config" || fail 'migration changed a symlink target'
printf 'API auth tests passed.\n'
