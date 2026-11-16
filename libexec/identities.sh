#!/usr/bin/env bash
# Account lifecycle, credentials, native permissions, and common launcher helpers.
# Loaded by bin/codex-home; no commands run at import.

usage() {
  cat <<'EOF'
Keep Codex accounts separate. Choose one for each project.

Usage: codex-home COMMAND [ARGS...]

Set up an account
  create-subscription NAME [file|keyring]  Create a separate ChatGPT login
  login NAME                   Sign in
  create-umgpt                 Create a U-M Toolkit identity
  set-key NAME                 Save an API key with a hidden prompt

Use a project
  project NAME [DIR]           Assign an identity to a folder
  run [NAME] [CODEX_ARGS...]    Start Codex; omit NAME in an active project
  run -- resume --last         Resume in the active project
  vscode-project [DIR]         Open a labeled VS Code window
  vscode NAME [DIR]            Open VS Code with a specific identity
  current                     Check the selected identity
  list                        List identities

Optional command sandbox
  set-sandbox NAME workspace-write   Allow project edits
  set-sandbox NAME read-only         Restrict writes further
  set-sandbox NAME inherit           Use remaining Codex defaults

Start here: README.md. Setup: INSTALLATION.md.
API providers, model settings, maintenance, and all commands: docs/commands.md.
NAME is a local label; "default" uses existing ~/.codex.
EOF
}

die() {
  printf 'codex-home: %s\n' "$*" >&2
  exit 1
}

data_helper() {
  command -v python3 >/dev/null 2>&1 || die "Python 3.11 or newer is required"
  [[ -f "$CODEX_DATA_HELPER" ]] || die "missing data helper: $CODEX_DATA_HELPER; reinstall the launcher"
  if [[ "${1:-}" == --exec ]]; then
    shift
    exec python3 -I "$CODEX_DATA_HELPER" "$@"
  fi
  python3 -I "$CODEX_DATA_HELPER" "$@"
}

identity_command() {
  local name="$1" home="$2"
  shift 2
  data_helper launch "$name" "$home" "$@"
}

exec_identity_command() {
  local name="$1" home="$2"
  shift 2
  data_helper --exec launch "$name" "$home" "$@"
}

validate_name() {
  local name="$1"
  [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] ||
    die "identity names may contain only letters, numbers, underscores, and hyphens"
}

validate_env_name() {
  local name="$1"
  [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] ||
    die "invalid environment-variable name: $name"
}

validate_provider_name() {
  local name="$1"
  case "$name" in
    openai|ollama|lmstudio|amazon-bedrock)
      die "'$name' is a reserved Codex provider ID; choose another identity name"
      ;;
  esac
}

validate_single_line() {
  local description="$1"
  local value="$2"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] ||
    die "$description must fit on one line"
}

is_model_id() {
  [[ "$1" != *$'\n'* && "$1" != *$'\r'* &&
    "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._:/@+-]*$ ]]
}

validate_model_id() {
  local model="$1"
  is_model_id "$model" ||
    die "invalid model ID '$model'"
}

toml_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

shell_double_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\$/\\\$}"
  value="${value//\`/\\\`}"
  printf '"%s"' "$value"
}

curl_config_quote() {
  local value="$1"
  validate_single_line "curl configuration value" "$value"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

identity_home() {
  local name="$1"
  if [[ "$name" == "default" ]]; then
    printf '%s\n' "$HOME/.codex"
  else
    printf '%s\n' "$CODEX_HOMES_ROOT/$name"
  fi
}

identity_kind() {
  local name="$1"
  local home
  home="$(identity_home "$name")"

  if [[ "$name" == "default" ]]; then
    printf '%s\n' "codex-default"
  elif [[ -f "$home/.identity-kind" ]]; then
    sed -n '1p' "$home/.identity-kind"
  else
    printf '%s\n' "unknown"
  fi
}

identity_label() {
  local name="$1"
  local kind
  kind="$(identity_kind "$name")"

  case "$kind" in
    codex-default) printf '%s\n' "DEFAULT (~/.codex)" ;;
    chatgpt-subscription) printf '%s subscription\n' "$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')" ;;
    api-key) printf 'API: %s\n' "$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')" ;;
    umgpt-openai) printf 'U-M GPT (Azure OpenAI): %s\n' "$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')" ;;
    umgpt-low) printf 'U-M GPT LOW-SENSITIVITY: %s\n' "$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')" ;;
    *) printf '%s\n' "$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')" ;;
  esac
}

is_api_key_kind() {
  case "$1" in
    api-key|umgpt-openai|umgpt-low) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_identity() {
  local name="$1"
  local home
  validate_name "$name"
  home="${2:-$(identity_home "$name")}"
  [[ -d "$home" ]] || die "identity '$name' does not exist at $home"
  [[ -f "$home/config.toml" ]] || die "identity '$name' has no config.toml at $home"
}

ensure_new_identity() {
  local name="$1"
  local home
  validate_name "$name"
  [[ "$name" != "default" ]] || die "'default' is reserved for the existing ~/.codex identity"
  home="$(identity_home "$name")"
  [[ ! -e "$home" ]] || die "refusing to overwrite existing path: $home"
}

write_identity_kind() {
  local home="$1"
  local kind="$2"
  printf '%s\n' "$kind" > "$home/.identity-kind"
  chmod 600 "$home/.identity-kind"
}

# Edit only root settings. This is deliberately a small TOML reader: arrays and
# inline tables are tracked, but multiline strings and custom permissions are
# left to the user's editor rather than risking a change inside another value.
sandbox_config() {
  local config="$1" action="$2" mode="${3:-}"
  awk -v action="$action" -v mode="$mode" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    function unsupported() { failed = 1; exit 2 }
    function scan(value,    i, c, quote, escaped) {
      for (i = 1; i <= length(value); i++) {
        c = substr(value, i, 1)
        if (quote == "\"") {
          if (escaped) escaped = 0
          else if (c == "\\") escaped = 1
          else if (c == quote) quote = ""
        } else if (quote == "\047") {
          if (c == quote) quote = ""
        } else {
          if (c == "#") break
          if (substr(value, i, 3) == "\"\"\"" ||
              substr(value, i, 3) == "\047\047\047") unsupported()
          if (c == "\"" || c == "\047") quote = c
          else if (c == "[") square++
          else if (c == "]") square--
          else if (c == "{") curly++
          else if (c == "}") curly--
          if (square < 0 || curly < 0) unsupported()
        }
      }
      if (quote != "") unsupported()
    }
    BEGIN {
      root = 1
      if (action == "write" && mode != "inherit") {
        print "sandbox_mode = \"" mode "\""
        print "approval_policy = \"on-request\""
        print "approvals_reviewer = \"user\""
      }
    }
    {
      skip = 0
      line = trim($0)
      # Custom permission profiles can supersede sandbox_mode. Refuse them
      # conservatively, including their quoted TOML table spelling.
      if (line ~ /^\[/ && (!root || (!square && !curly))) {
        table = line
        sub(/^\[+[[:space:]]*/, "", table)
        if (index(table, "\\")) unsupported()
        gsub(/["\047]/, "", table)
        if (table ~ /^(permissions|sandbox_mode|approval_policy|approvals_reviewer)([[:space:].]|\])/)
          unsupported()
      }
      if (root && !square && !curly && line ~ /^\[/) root = 0
      if (root && line !~ /^($|#)/) {
        continuation = square || curly
        scan($0)
        if (!continuation) {
          if (line !~ /^[^=]+=/) unsupported()
          key = line
          sub(/=.*/, "", key)
          key = trim(key)
          if (index(key, "\\")) unsupported()
          gsub(/["\047]/, "", key)
          key = trim(key)
          if (key ~ /^(permissions|default_permissions)([[:space:].]|$)/)
            unsupported()
          if (key ~ /^(sandbox_mode|approval_policy|approvals_reviewer)[[:space:]]*\./)
            unsupported()
          if (key == "sandbox_mode" || key == "approval_policy" ||
              key == "approvals_reviewer") {
            if (seen[key]++) unsupported()
            value = line
            sub(/^[^=]*=[[:space:]]*/, "", value)
            if (value !~ /^"[^"\\]*"[[:space:]]*(#.*)?$/ &&
                value !~ /^\047[^\047]*\047[[:space:]]*(#.*)?$/) unsupported()
            value = substr(value, 2)
            sub(/["\047].*$/, "", value)
            saved[key] = value
            skip = 1
          }
        }
      }
      if (action == "write" && !skip) print $0
    }
    END {
      if (failed || square || curly) exit 2
      if (action == "show") {
        sandbox = saved["sandbox_mode"]
        if (!seen["sandbox_mode"]) print "inherited (Codex defaults)"
        else if (sandbox ~ /^(read-only|workspace-write|danger-full-access)$/) {
          approval = saved["approval_policy"]
          reviewer = saved["approvals_reviewer"]
          if (approval == "") approval = "inherited approvals"
          else if (approval !~ /^(on-request|never)$/) approval = "custom approvals"
          if (reviewer == "") reviewer = "inherited review"
          else if (reviewer !~ /^(user|auto_review)$/) reviewer = "custom review"
          print sandbox " (" approval "; " reviewer ")"
        } else print "custom configuration; inspect config.toml"
      }
    }
  ' "$config"
}

set_sandbox() (
  [[ $# -eq 2 ]] ||
    die "usage: codex-home set-sandbox NAME read-only|workspace-write|inherit"
  local name="$1" mode="$2" home config staged=""
  case "$mode" in
    read-only|workspace-write|inherit) ;;
    *) die "sandbox mode must be read-only, workspace-write, or inherit" ;;
  esac
  ensure_identity "$name"
  home="$(identity_home "$name")"
  config="$home/config.toml"
  [[ ! -L "$config" ]] || die "refusing to replace a symlink: $config; edit sandbox settings manually"
  umask 077
  staged="$(mktemp "${config}.codex-home.XXXXXX")" || die "could not stage $config"
  trap 'rm -f -- "$staged"' EXIT
  if ! sandbox_config "$config" write "$mode" > "$staged"; then
    die "unsupported or custom permission configuration in $config; edit sandbox settings manually"
  fi
  chmod 600 "$staged"
  mv -- "$staged" "$config"
  printf 'Sandbox default for %s: %s\n' "$name" "$mode"
  printf '%s\n' 'Restart Codex CLI or reload VS Code and start a new chat.'
  printf '%s\n' 'These are defaults; profiles, project/CLI settings, and managed policy may override them.'
)

create_subscription() {
  [[ $# -ge 1 && $# -le 2 ]] || die "usage: codex-home create-subscription NAME [file|keyring]"
  local name="$1" store="${2:-file}"
  local home
  case "$store" in
    file|keyring) ;;
    *) die "credential store must be file or keyring" ;;
  esac
  ensure_new_identity "$name"
  home="$(identity_home "$name")"

  umask 077
  mkdir -p "$home"
  cat > "$home/config.toml" <<EOF
# Authentication is scoped to this CODEX_HOME. Run: codex-home login <identity>
cli_auth_credentials_store = "$store"

[tui]
status_line = ["model-with-reasoning", "context-remaining", "current-dir"]
terminal_title = ["app-name", "project", "model"]
EOF
  chmod 600 "$home/config.toml"
  write_identity_kind "$home" "chatgpt-subscription"

  printf 'Created ChatGPT subscription identity %s\n' "$name"
  printf '  CODEX_HOME: %s\n' "$home"
  printf 'Next: %s login %s\n' "$0" "$name"
}

create_api_identity() {
  local name="$1"
  local base_url="$2"
  local model="$3"
  local key_env="$4"
  local api_version="${5:-}"
  local kind="${6:-api-key}"
  local provider_label="Codex identity: $name"
  local home auth

  case "$kind" in
    umgpt-openai) provider_label="U-M GPT Toolkit ($name)" ;;
    umgpt-low) provider_label="U-M GPT Toolkit ($name; LOW-SENSITIVITY DATA ONLY)" ;;
  esac

  ensure_new_identity "$name"
  validate_provider_name "$name"
  validate_single_line "base URL" "$base_url"
  validate_single_line "model" "$model"
  validate_env_name "$key_env"
  data_helper validate-key-name "$key_env" || return
  if [[ -n "$api_version" ]]; then
    validate_single_line "API version" "$api_version"
  fi
  data_helper url "$base_url" || return
  [[ -n "$model" ]] || die "model may not be empty"
  home="$(identity_home "$name")"
  auth="$(data_helper auth-config "$home" "$key_env")" || return

  umask 077
  mkdir -p "$home"
  {
    printf 'model = %s\n' "$(toml_quote "$model")"
    printf 'model_provider = %s\n\n' "$(toml_quote "$name")"
    printf '[model_providers.%s]\n' "$name"
    printf 'name = %s\n' "$(toml_quote "$provider_label")"
    printf 'base_url = %s\n' "$(toml_quote "$base_url")"
    printf 'auth = %s\n' "$auth"
    if [[ -n "$api_version" ]]; then
      printf 'query_params = { api-version = %s }\n' "$(toml_quote "$api_version")"
    fi
    printf 'wire_api = "responses"\n\n'
    printf '[tui]\n'
    printf 'status_line = ["model-with-reasoning", "context-remaining", "current-dir"]\n'
    printf 'terminal_title = ["app-name", "project", "model"]\n'
  } > "$home/config.toml"
  chmod 600 "$home/config.toml"
  write_identity_kind "$home" "$kind"

  printf 'Created API identity %s\n' "$name"
  printf '  CODEX_HOME: %s\n' "$home"
  printf '  Provider:   %s\n' "$base_url"
  printf '  Model:      %s\n' "$model"
  printf '  Key entry:  %s (command-backed; not exported)\n' "$key_env"
  if [[ -n "$api_version" ]]; then
    printf '  API version:%s\n' " $api_version"
  fi
  printf 'Next: %s set-key %s\n' "$0" "$name"
}

create_api() {
  [[ $# -eq 4 ]] || die "usage: codex-home create-api NAME BASE_URL MODEL API_KEY_ENV"
  create_api_identity "$@"
}

create_azure() {
  [[ $# -eq 5 ]] ||
    die "usage: codex-home create-azure NAME BASE_URL MODEL API_KEY_ENV API_VERSION"
  create_api_identity "$@"
}

config_values() {
  local file="$1"
  local key="$2"
  sed -nE \
    -e "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\\1/p" \
    -e "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*'([^']*)'.*/\\1/p" \
    "$file"
}

config_value() {
  # Drain the producer so large configs cannot fail with SIGPIPE under pipefail.
  config_values "$1" "$2" | sed -n '1p'
}

api_key_env_for() {
  local name="$1"
  local home
  home="$(identity_home "$name")"
  data_helper key-name "$home"
}

prompt_secret() (
  local prompt="$1" secret terminal_settings restore_terminal
  terminal_settings="$(stty -g)" || return
  # Bash 3.2 can unwind local variables before running EXIT after a signal.
  printf -v restore_terminal 'stty %q || exit 1' "$terminal_settings"
  trap "$restore_terminal" EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  # Bash 3.2 can print read -s -p's prompt before disabling terminal echo.
  stty -echo || return
  printf '%s' "$prompt" >&2 || return
  IFS= read -r secret || return
  printf '\n' >&2 || return
  printf '%s' "$secret"
)

set_key() (
  [[ $# -eq 1 ]] || die "usage: codex-home set-key NAME"
  local name="$1"
  local home key_env secret destination
  ensure_identity "$name"
  is_api_key_kind "$(identity_kind "$name")" || die "identity '$name' is not an API-key identity"
  home="$(identity_home "$name")"
  key_env="$(api_key_env_for "$name")"
  [[ -n "$key_env" ]] || die "could not find a supported stored-key configuration in $home/config.toml"
  destination="$(data_helper credential-path "$home")" || return
  [[ ! -L "$destination" && ( ! -e "$destination" || -f "$destination" ) ]] ||
    die "refusing to replace a symlinked or nonregular credential file: $destination"
  [[ -t 0 ]] || die "set-key requires an interactive terminal so the key is not exposed"

  secret="$(prompt_secret "Enter $key_env for $name: ")" || return
  [[ -n "$secret" ]] || die "key may not be empty"
  validate_single_line "API key" "$secret"

  destination="$(printf '%s' "$secret" | data_helper store-key "$home" "$key_env")" || return
  unset secret
  printf 'Saved %s in %s with mode 600.\n' "$key_env" "$destination"
)

migrate_api_auth() {
  [[ $# -eq 1 ]] || die "usage: codex-home migrate-api-auth NAME"
  local name="$1" home result kind
  ensure_identity "$name"
  kind="$(identity_kind "$name")"
  is_api_key_kind "$kind" || die "migrate-api-auth is only for an API-key identity"
  home="$(identity_home "$name")"
  result="$(data_helper migrate-api-auth "$home" "$name" "$kind")" || return
  if [[ "$result" == already ]]; then
    printf '%s already uses command-backed API authentication.\n' "$name"
  else
    printf 'Migrated %s to command-backed API authentication using api-key.env.\n' "$name"
    printf '%s\n' "Restart Codex and quit this identity's VS Code instance before reopening it to clear inherited keys."
  fi
}

login_identity() {
  [[ $# -eq 1 ]] || die "usage: codex-home login NAME"
  local name="$1"
  local home
  ensure_identity "$name"
  [[ "$(identity_kind "$name")" == "chatgpt-subscription" ]] ||
    die "login is only for a ChatGPT subscription identity"
  home="$(identity_home "$name")"
  printf 'Opening ChatGPT login for %s using CODEX_HOME=%s\n' "$name" "$home"
  exec_identity_command "$name" "$home" codex login
}

run_identity() {
  local name
  local home label context_name scope
  local -a codex_args
  if [[ $# -eq 0 || "${1:-}" == -* ]]; then
    name="${CODEX_IDENTITY:-}"
    [[ -n "$name" ]] ||
      die "no active project context; enter a direnv-enabled project or use: codex-home run NAME"
    check_project_selection "$name" "${CODEX_HOME:-$(identity_home "$name")}" || return
    if [[ "${1:-}" == "--" ]]; then
      shift
    fi
  else
    name="$1"
    shift
  fi
  ensure_identity "$name"
  data_helper identity "$(identity_home "$name")" || return
  validate_umgpt_identity_config "$name" || return
  home="$(identity_home "$name")"
  data_helper launch-check "$home" "$@" || return
  label="$(identity_label "$name")"
  scope="$(identity_umgpt_scope "$name" 2>/dev/null || true)"
  if [[ -n "$scope" ]]; then
    prepare_umgpt_codex_args "$name" "$scope" "$@" || return
    # Bash 3.2 treats an empty array as unset under nounset; preserve zero args.
    codex_args=(--model "$UMGPT_SCOPED_MODEL" ${UMGPT_SCOPED_ARGS[@]+"${UMGPT_SCOPED_ARGS[@]}"})
  else
    codex_args=("$@")
  fi
  export CODEX_HOME="$home"
  export CODEX_IDENTITY="$name"

  if [[ -t 0 && -t 1 && -t 2 && "${TERM:-dumb}" != "dumb" ]]; then
    context_name="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
    # Save the terminal's title, then keep the context visible while Codex runs.
    # Clear our label on exit; terminals with a title stack restore the old title.
    printf '\033[22;0t\033]0;[CODEX: %s]\007' "$context_name" >&2
    trap 'printf "\033]0;\007\033[23;0t" >&2' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    printf '\n\033[1;7m  [CODEX: %s]  \033[0m\n\n' "$context_name" >&2

    # An empty list stops Codex replacing the title with its project/model.
    if [[ "$scope" == "low-sensitivity" ]]; then
      printf '\033[1;31m  LOW-SENSITIVITY DATA ONLY: verify the selected model before use.  \033[0m\n\n' >&2
    fi
    identity_command "$name" "$home" codex -c 'tui.terminal_title=[]' ${codex_args[@]+"${codex_args[@]}"}
    return
  fi

  printf 'Codex identity: %s\n' "$label" >&2
  if [[ "$scope" == "low-sensitivity" ]]; then
    printf '%s\n' 'LOW-SENSITIVITY DATA ONLY: verify the selected model before use.' >&2
  fi
  exec_identity_command "$name" "$home" codex ${codex_args[@]+"${codex_args[@]}"}
}

doctor_identity() {
  [[ $# -eq 1 ]] || die "usage: codex-home doctor NAME"
  local name="$1"
  local home
  ensure_identity "$name"
  validate_umgpt_identity_config "$name" || return
  home="$(identity_home "$name")"
  data_helper launch-check "$home" || return
  printf 'Checking %s with CODEX_HOME=%s\n' "$(identity_label "$name")" "$home"
  exec_identity_command "$name" "$home" codex --strict-config doctor --summary
}

show_identity() {
  local name="$1"
  local home="${2:-}"
  local kind label config model provider base_url key_env key_status auth_status auth_store umgpt_scope sandbox
  if [[ -z "$home" ]]; then
    ensure_identity "$name"
    home="$(identity_home "$name")"
  fi
  kind="$(identity_kind "$name")"
  label="$(identity_label "$name")"
  config="$home/config.toml"
  model=""
  provider=""
  base_url=""
  key_env=""
  if [[ -f "$config" ]]; then
    model="$(config_value "$config" "model")"
    provider="$(config_value "$config" "model_provider")"
    base_url="$(data_helper provider-value "$home" base_url)" || return
    key_env="$(data_helper key-name "$home")" || return
  fi
  [[ -n "$model" ]] || model="Codex default"
  [[ -n "$provider" ]] || provider="openai"

  printf 'Codex identity : %s\n' "$label"
  printf 'Auth kind      : %s\n' "$kind"
  printf 'CODEX_HOME     : %s\n' "$home"
  printf 'Config         : %s\n' "$config"
  printf 'Model          : %s\n' "$model"
  printf 'Provider       : %s\n' "$provider"
  sandbox="$(sandbox_config "$config" show 2>/dev/null)" || sandbox="custom configuration; inspect config.toml"
  printf 'Sandbox default: %s\n' "$sandbox"
  umgpt_scope="$(identity_umgpt_scope "$name" 2>/dev/null || true)"
  case "$umgpt_scope" in
    openai-only) printf '%s\n' 'Model scope     : U-M Azure OpenAI text models only' ;;
    low-sensitivity) printf '%s\n' 'Model scope     : broader U-M text models; LOW-SENSITIVITY DATA ONLY' ;;
    unset) printf '%s\n' 'Model scope     : UNSET; run set-umgpt-scope before launching Codex' ;;
  esac
  if [[ -n "$base_url" ]]; then
    printf 'Base URL       : %s\n' "$base_url"
  fi
  if [[ -n "$key_env" ]]; then
    key_env="$(data_helper key-name "$home")" || return
    local credential_file
    credential_file="$(data_helper credential-path "$home")" || return
    if [[ -f "$credential_file" ]]; then
      key_status="stored; use codex-home run"
    elif [[ -n "${!key_env:-}" && -n "$(data_helper provider-value "$home" env_key)" ]]; then
      key_status="present in caller; explicit environment grant required"
    else
      key_status="MISSING; run codex-home set-key $name"
    fi
    printf 'API key entry : %s (%s)\n' "$key_env" "$key_status"
  elif [[ "$kind" == "chatgpt-subscription" ]]; then
    auth_store="$(data_helper root-value "$home" cli_auth_credentials_store)" || return
    if [[ "$auth_store" == keyring ]]; then
      auth_status="OS credential store selected; check: codex-home run $name login status"
    elif [[ -f "$home/auth.json" ]]; then
      auth_status="auth.json present"
    else
      auth_status="not logged in; run codex-home login $name"
    fi
    printf 'Credentials    : %s\n' "$auth_status"
  fi
}

show_named() {
  [[ $# -eq 1 ]] || die "usage: codex-home show NAME"
  show_identity "$1"
}

show_current() {
  local home name
  home="${CODEX_HOME:-$HOME/.codex}"
  name="${CODEX_IDENTITY:-}"
  if [[ -z "$name" ]]; then
    if [[ "$home" == "$HOME/.codex" ]]; then
      name="default"
    else
      name="$(basename "$home")"
    fi
  fi
  check_project_selection "$name" "$home" || return
  show_identity "$name" "$home"
}

list_identity_names() {
  local home name

  if [[ -f "$HOME/.codex/config.toml" ]]; then
    printf '%s\n' "default"
  fi

  [[ -d "$CODEX_HOMES_ROOT" ]] || return 0
  while IFS= read -r home; do
    name="$(basename "$home")"
    if [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ && -f "$home/config.toml" ]]; then
      printf '%s\n' "$name"
    fi
  done < <(find "$CODEX_HOMES_ROOT" -mindepth 1 -maxdepth 1 -type d -print | sort)
}

list_identities() {
  [[ $# -le 1 ]] || die "usage: codex-home list [--names]"
  if [[ "${1:-}" == "--names" ]]; then
    list_identity_names
    return 0
  fi
  [[ $# -eq 0 ]] || die "usage: codex-home list [--names]"

  local home name
  printf '%-24s %-22s %s\n' "IDENTITY" "KIND" "CODEX_HOME"
  printf '%-24s %-22s %s\n' "default" "codex-default" "$HOME/.codex"
  [[ -d "$CODEX_HOMES_ROOT" ]] || return 0
  while IFS= read -r home; do
    name="$(basename "$home")"
    printf '%-24s %-22s %s\n' "$name" "$(identity_kind "$name")" "$home"
  done < <(find "$CODEX_HOMES_ROOT" -mindepth 1 -maxdepth 1 -type d -print | sort)
}

share_skills() {
  [[ $# -ge 1 && $# -le 2 ]] ||
    die "usage: codex-home share-skills NAME [SOURCE_DIR]"
  local name="$1"
  local source_dir="${2:-${CODEX_SKILLS_SOURCE:-$HOME/.codex/skills}}"
  local source_abs home target_dir entry skill_name target_entry linked skipped

  ensure_identity "$name"
  [[ -d "$source_dir" ]] || die "skills source does not exist: $source_dir"
  source_abs="$(cd "$source_dir" && pwd -P)"
  home="$(identity_home "$name")"
  target_dir="$home/skills"

  if [[ "$name" == "default" && "$source_abs" == "$HOME/.codex/skills" ]]; then
    printf 'The default identity already owns the canonical skills directory: %s\n' "$source_abs"
    return 0
  fi

  umask 077
  mkdir -p "$target_dir"
  linked=0
  skipped=0

  while IFS= read -r entry; do
    skill_name="$(basename "$entry")"
    target_entry="$target_dir/$skill_name"

    # Each Codex installation manages its own bundled system skills.
    if [[ "$skill_name" == ".system" ]]; then
      continue
    fi

    if [[ ! -e "$target_entry" && ! -L "$target_entry" ]]; then
      ln -s "$entry" "$target_entry"
      printf 'Linked %-32s -> %s\n' "$skill_name" "$entry"
      linked=$((linked + 1))
    elif [[ -L "$target_entry" && "$(readlink "$target_entry")" == "$entry" ]]; then
      :
    else
      printf 'Skipped %-31s (target already exists: %s)\n' "$skill_name" "$target_entry" >&2
      skipped=$((skipped + 1))
    fi
  done < <(find "$source_abs" -mindepth 1 -maxdepth 1 -print)

  printf 'Skills for %s: %d linked, %d conflicts skipped.\n' "$name" "$linked" "$skipped"
}

share_skills_all() {
  [[ $# -le 1 ]] || die "usage: codex-home share-skills-all [SOURCE_DIR]"
  local source_dir="${1:-${CODEX_SKILLS_SOURCE:-$HOME/.codex/skills}}"
  local home name found
  [[ -d "$source_dir" ]] || die "skills source does not exist: $source_dir"
  found=0

  if [[ -d "$CODEX_HOMES_ROOT" ]]; then
    while IFS= read -r home; do
      name="$(basename "$home")"
      if [[ -f "$home/config.toml" ]]; then
        share_skills "$name" "$source_dir"
        found=$((found + 1))
      fi
    done < <(find "$CODEX_HOMES_ROOT" -mindepth 1 -maxdepth 1 -type d -print | sort)
  fi

  [[ "$found" -gt 0 ]] || die "no additional identities found under $CODEX_HOMES_ROOT"
}

