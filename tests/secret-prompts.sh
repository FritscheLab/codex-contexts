#!/usr/bin/env bash
# Public credential prompts restore terminal settings after success or cancellation.
set -euo pipefail

SECRET_TEST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$SECRET_TEST_REPO/tests/common.sh"
export SECRET_TEST_TOOL="$(resolve_codex_home_tool "$SECRET_TEST_REPO/bin")"
export SECRET_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-secret-prompts.XXXXXX")"
trap 'rm -rf -- "$SECRET_TEST_ROOT"' EXIT
export HOME="$SECRET_TEST_ROOT/home"
export CODEX_HOMES_ROOT="$SECRET_TEST_ROOT/homes"
export SECRET_TEST_STTY="$(command -v stty)"
mkdir -p "$HOME" "$SECRET_TEST_ROOT/bin"
export PATH="$SECRET_TEST_ROOT/bin:$PATH"
fail() { printf 'Secret prompt test failure: %s\n' "$*" >&2; exit 1; }

cat >"$SECRET_TEST_ROOT/bin/curl" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' '{"data":[{"id":"synthetic-model"}]}'
EOF
chmod +x "$SECRET_TEST_ROOT/bin/curl"

# A slow restore exposes a CLI that exits while its prompt is still cleaning up.
cat >"$SECRET_TEST_ROOT/bin/stty" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${secret:-}" && "$secret" != inherited-environment-value ]]; then
  printf 'Terminal command received the prompted key in its environment.\n' >&2
  exit 122
fi
if [[ "${SECRET_TEST_OUTCOME:-}" == interrupt && "$1" != -* ]]; then
  sleep 0.2
fi
exec "$SECRET_TEST_STTY" "$@"
EOF
chmod +x "$SECRET_TEST_ROOT/bin/stty"

"$SECRET_TEST_TOOL" create-api prompt-test https://provider.example.test/v1 \
  synthetic-model PROMPT_TEST_KEY >/dev/null

# The wrapper keeps the terminal alive after the CLI exits so restoration can
# be checked on EOF and Ctrl-C as well as success. Its caught SIGINT does not
# make external children inherit an ignored signal.
cat >"$SECRET_TEST_ROOT/terminal-wrapper" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
original_settings="$(stty -g)" || exit 120
trap ':' INT
"$@"
command_status=$?
if [[ "$(stty -g)" != "$original_settings" ]]; then
  printf '\nTerminal settings changed after the CLI exited.\n' >&2
  exit 121
fi
printf '\nPROMPT_STATUS=%s\n' "$command_status"
EOF

export SECRET_TEST_SECRET='synthetic-hidden-input'
for action in set-key probe-models; do
  if [[ "$action" == set-key ]]; then
    argument=prompt-test
    prompt='Enter PROMPT_TEST_KEY for prompt-test: '
  else
    argument=https://provider.example.test/v1
    prompt="API key for $argument: "
  fi
  for outcome in success eof interrupt; do
    printf 'PROMPT_TEST_KEY="original-synthetic-key"\n' \
      >"$CODEX_HOMES_ROOT/prompt-test/api-key.env"
    chmod 600 "$CODEX_HOMES_ROOT/prompt-test/api-key.env"
    case "$outcome" in
      success) expected_status=0 ;;
      eof) expected_status=1 ;;
      interrupt) expected_status=130 ;;
    esac
    SECRET_TEST_ACTION="$action" SECRET_TEST_ARGUMENT="$argument" \
    SECRET_TEST_PROMPT="$prompt" SECRET_TEST_OUTCOME="$outcome" \
    SECRET_TEST_STATUS="$expected_status" expect -c '
      set timeout 10
      spawn -noecho env -i HOME=$env(HOME) \
        CODEX_HOMES_ROOT=$env(CODEX_HOMES_ROOT) PATH=$env(PATH) \
        SECRET_TEST_STTY=$env(SECRET_TEST_STTY) SECRET_TEST_OUTCOME=$env(SECRET_TEST_OUTCOME) \
        secret=inherited-environment-value \
        bash $env(SECRET_TEST_ROOT)/terminal-wrapper \
        $env(SECRET_TEST_TOOL) $env(SECRET_TEST_ACTION) $env(SECRET_TEST_ARGUMENT)
      expect {
        -exact $env(SECRET_TEST_PROMPT) {}
        timeout { exit 124 }
        eof { exit 125 }
      }
      if {[catch {exec stty -a < $spawn_out(slave,name) 2>@1} terminal_modes]} {
        puts stderr $terminal_modes
        exit 126
      }
      if {[regexp {(^|[[:space:];])echo([[:space:];]|$)} $terminal_modes]} {
        puts stderr "terminal echo was enabled when the prompt appeared"
        exit 126
      }
      switch $env(SECRET_TEST_OUTCOME) {
        success { send -- "$env(SECRET_TEST_SECRET)\r" }
        eof { send -- "\004" }
        interrupt { send -- "\003" }
      }
      expect {
        -re {PROMPT_STATUS=([0-9]+)\r?\n} {
          if {$expect_out(1,string) != $env(SECRET_TEST_STATUS)} { exit 127 }
        }
        timeout { exit 124 }
        eof { exit 125 }
      }
      expect eof
      exit [lindex [wait] 3]
    ' >"$SECRET_TEST_ROOT/output" || {
      cat "$SECRET_TEST_ROOT/output" >&2
      fail "$action did not restore the terminal with the expected status on $outcome"
    }
    if grep -Fq -- "$SECRET_TEST_SECRET" "$SECRET_TEST_ROOT/output"; then
      fail "$action echoed the entered secret"
    fi
    expected_key=original-synthetic-key
    if [[ "$action" == set-key && "$outcome" == success ]]; then
      expected_key="$SECRET_TEST_SECRET"
    fi
    actual_key="$(python3 -I "$SECRET_TEST_REPO/libexec/codex_contexts.py" \
      secret "$CODEX_HOMES_ROOT/prompt-test")"
    [[ "$actual_key" == "$expected_key" ]] || fail "$action changed the stored key on $outcome"
  done
done

printf 'Secret prompt tests passed.\n'
