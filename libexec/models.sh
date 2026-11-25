#!/usr/bin/env bash
# U-M model scopes, saved defaults, discovery, and picker catalogs.

is_umgpt_general_text_model() {
  local normalized
  normalized="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$normalized" in
    *image*|*embedding*) return 1 ;;
    *) return 0 ;;
  esac
}

is_umgpt_openai_text_model() {
  is_umgpt_general_text_model "$1" || return 1
  case "$1" in
    gpt-*|o[0-9]*) return 0 ;;
    *) return 1 ;;
  esac
}

validate_umgpt_model() {
  local scope="$1"
  local model="$2"
  validate_model_id "$model"
  case "$scope" in
    openai-only)
      is_umgpt_openai_text_model "$model" ||
        die "U-M GPT Azure OpenAI identities require a GPT or o-series text model; use create-umgpt-low for '$model'"
      ;;
    low-sensitivity)
      is_umgpt_general_text_model "$model" ||
        die "'$model' is an image-generation or embedding model, not a general Codex text model"
      ;;
    *) die "unknown U-M GPT model scope: $scope" ;;
  esac
}

umgpt_scope_for_kind() {
  case "$1" in
    umgpt-openai) printf '%s\n' "openai-only" ;;
    umgpt-low) printf '%s\n' "low-sensitivity" ;;
    *) return 1 ;;
  esac
}

identity_umgpt_scope() {
  local name="$1"
  local home kind base_url
  home="$(identity_home "$name")"
  kind="$(identity_kind "$name")"
  if umgpt_scope_for_kind "$kind"; then
    return 0
  fi
  if [[ "$kind" == "api-key" && -f "$home/config.toml" ]]; then
    base_url="$(data_helper provider-value "$home" base_url)" || return
    if [[ "${base_url%/}" == "$UMGPT_BASE_URL" ]]; then
      printf '%s\n' "unset"
      return 0
    fi
  fi
  return 1
}

write_umgpt_models_file() {
  local openai_model="$1"
  local low_model="$2"
  local openai_order="${3:-[]}" low_order="${4:-[]}"
  local models_dir staged
  validate_umgpt_model "openai-only" "$openai_model"
  validate_umgpt_model "low-sensitivity" "$low_model"
  openai_order="$(validate_umgpt_model_order openai-only "$openai_order")" || return
  low_order="$(validate_umgpt_model_order low-sensitivity "$low_order")" || return
  models_dir="$(dirname "$UMGPT_MODELS_FILE")"
  [[ ! -d "$UMGPT_MODELS_FILE" ]] ||
    die "U-M GPT models file is a directory: $UMGPT_MODELS_FILE"
  umask 077
  mkdir -p "$models_dir"
  staged="$(mktemp "${UMGPT_MODELS_FILE}.codex-home.XXXXXX")" ||
    die "could not stage $UMGPT_MODELS_FILE"
  {
    printf '%s\n' '# Your model settings. After editing, run: codex-home apply-model-settings'
    printf '%s\n' '# Default first, then your preferred models, then remaining models by family/version.'
    printf 'umgpt = %s\n' "$(toml_quote "$openai_model")"
    printf 'umgpt_low = %s\n' "$(toml_quote "$low_model")"
    printf '\n%s\n' '# Optional preferred order. Keep each array on one line; [] uses automatic order.'
    printf 'umgpt_order = %s\n' "$openai_order"
    printf 'umgpt_low_order = %s\n' "$low_order"
  } > "$staged"
  chmod 600 "$staged"
  mv "$staged" "$UMGPT_MODELS_FILE"
}

validate_umgpt_model_order() {
  local scope="$1" value="$2" id
  if [[ "$value" == '[]' ]]; then printf '%s\n' '[]'; return; fi
  command -v jq >/dev/null 2>&1 || die "jq is required for model order settings"
  value="$(jq -ce 'if type == "array" and all(.[]; type == "string")
    then . else error("expected an array of model IDs") end' <<< "$value" 2>/dev/null)" ||
    die "model order must be a single-line array of quoted model IDs"
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    validate_umgpt_model "$scope" "$id"
  done < <(jq -r '.[]' <<< "$value")
  jq -e 'all(.[]; length > 0 and (test("[\\r\\n]") | not))' <<< "$value" >/dev/null ||
    die "model order contains an empty or multiline model ID"
  printf '%s\n' "$value"
}

umgpt_models_file_value() {
  local file="$1"
  local requested_key="$2"
  local line line_number assignment_pattern empty_pattern key model
  local openai_model low_model openai_seen low_seen
  local order_pattern order_key order_value order_seen=" " openai_order='[]' low_order='[]'
  [[ -f "$file" ]] || die "U-M GPT models file is not a regular file: $file"
  assignment_pattern='^[[:space:]]*(umgpt|umgpt_low)[[:space:]]*=[[:space:]]*"([^"]+)"[[:space:]]*(#.*)?$'
  empty_pattern='^[[:space:]]*(#.*)?$'
  order_pattern='^[[:space:]]*(umgpt_order|umgpt_low_order)[[:space:]]*=[[:space:]]*(\[.*\])[[:space:]]*(#.*)?$'
  line_number=0
  openai_model=""
  low_model=""
  openai_seen=0
  low_seen=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    if [[ "$line" =~ $empty_pattern ]]; then
      continue
    fi
    if [[ "$line" =~ $order_pattern ]]; then
      order_key="${BASH_REMATCH[1]}"
      order_value="${BASH_REMATCH[2]}"
      [[ "$order_seen" != *" $order_key "* ]] || die "duplicate '$order_key' in $file"
      order_seen+="$order_key "
      if [[ "$order_key" == umgpt_order ]]; then
        openai_order="$(validate_umgpt_model_order openai-only "$order_value")" || return
      else
        low_order="$(validate_umgpt_model_order low-sensitivity "$order_value")" || return
      fi
      continue
    fi
    if [[ ! "$line" =~ $assignment_pattern ]]; then
      die "unsupported line $line_number in $file; use quoted defaults and single-line umgpt_order/umgpt_low_order arrays"
    fi
    key="${BASH_REMATCH[1]}"
    model="${BASH_REMATCH[2]}"
    case "$key" in
      umgpt)
        [[ "$openai_seen" -eq 0 ]] || die "duplicate 'umgpt' in $file"
        openai_model="$model"
        openai_seen=1
        ;;
      umgpt_low)
        [[ "$low_seen" -eq 0 ]] || die "duplicate 'umgpt_low' in $file"
        low_model="$model"
        low_seen=1
        ;;
    esac
  done < "$file"
  [[ "$openai_seen" -eq 1 ]] || die "missing 'umgpt' in $file"
  [[ "$low_seen" -eq 1 ]] || die "missing 'umgpt_low' in $file"
  validate_umgpt_model "openai-only" "$openai_model"
  validate_umgpt_model "low-sensitivity" "$low_model"
  case "$requested_key" in
    umgpt) printf '%s\n' "$openai_model" ;;
    umgpt_low) printf '%s\n' "$low_model" ;;
    umgpt_order) printf '%s\n' "$openai_order" ;;
    umgpt_low_order) printf '%s\n' "$low_order" ;;
    *) die "unknown U-M GPT models-file key: $requested_key" ;;
  esac
}

umgpt_repository_default_model() {
  local scope="$1"
  local key
  [[ -f "$UMGPT_REPOSITORY_MODELS_FILE" ]] ||
    die "repository U-M GPT defaults not found: $UMGPT_REPOSITORY_MODELS_FILE"
  case "$scope" in
    openai-only) key="umgpt" ;;
    low-sensitivity) key="umgpt_low" ;;
    *) die "unknown U-M GPT model scope: $scope" ;;
  esac
  umgpt_models_file_value "$UMGPT_REPOSITORY_MODELS_FILE" "$key"
}

ensure_umgpt_models_file() {
  local openai_model low_model home candidate base_url
  if [[ ! -e "$UMGPT_MODELS_FILE" ]]; then
    openai_model="$(umgpt_repository_default_model "openai-only")" || return
    low_model="$(umgpt_repository_default_model "low-sensitivity")" || return
    home="$(identity_home "umgpt")"
    if [[ -f "$home/config.toml" ]]; then
      candidate="$(data_helper root-value "$home" model)" || return
      base_url="$(data_helper provider-value "$home" base_url)" || return
      if [[ "${base_url%/}" == "$UMGPT_BASE_URL" ]] &&
        is_model_id "$candidate" && is_umgpt_openai_text_model "$candidate"; then
        openai_model="$candidate"
      fi
    fi
    home="$(identity_home "umgpt-low")"
    if [[ -f "$home/config.toml" ]]; then
      candidate="$(data_helper root-value "$home" model)" || return
      base_url="$(data_helper provider-value "$home" base_url)" || return
      if [[ "${base_url%/}" == "$UMGPT_BASE_URL" ]] &&
        is_model_id "$candidate" && is_umgpt_general_text_model "$candidate"; then
        low_model="$candidate"
      fi
    fi
    write_umgpt_models_file "$openai_model" "$low_model" \
      "$(umgpt_models_file_value "$UMGPT_REPOSITORY_MODELS_FILE" umgpt_order)" \
      "$(umgpt_models_file_value "$UMGPT_REPOSITORY_MODELS_FILE" umgpt_low_order)"
  fi
  [[ -f "$UMGPT_MODELS_FILE" ]] ||
    die "U-M GPT models file is not a regular file: $UMGPT_MODELS_FILE"
}

umgpt_default_model() {
  local scope="$1"
  local key
  ensure_umgpt_models_file || return
  case "$scope" in
    openai-only) key="umgpt" ;;
    low-sensitivity) key="umgpt_low" ;;
    *) die "unknown U-M GPT model scope: $scope" ;;
  esac
  umgpt_models_file_value "$UMGPT_MODELS_FILE" "$key"
}

check_umgpt_default_identity() {
  local identity="$1"
  local scope="$2"
  local model="$3"
  local home current_scope
  home="$(identity_home "$identity")"
  [[ -d "$home" ]] || return 0
  ensure_identity "$identity"
  current_scope="$(identity_umgpt_scope "$identity" 2>/dev/null || true)"
  [[ "$current_scope" == "$scope" ]] ||
    die "identity '$identity' is not classified as '$scope'"
  [[ ! -L "$home/config.toml" ]] || die "refusing to edit a symlinked config: $home/config.toml"
  data_helper stage-model-config "$home/config.toml" /dev/null "$model"
}

sync_umgpt_default_identity() (
  local identity="$1" scope="$2" model="$3"
  local home scratch current_model catalog configured
  home="$(identity_home "$identity")"
  if [[ ! -d "$home" ]]; then
    printf 'Skipped %-9s (identity not created yet).\n' "$identity"
    return
  fi
  home="$(cd "$home" && pwd -P)"
  umask 077
  scratch="$(mktemp -d "$home/.model-order.XXXXXX")"
  trap '[[ -f "$scratch/retain" ]] || rm -rf -- "$scratch"' EXIT
  snapshot_model_config "$home" "$scratch" || return
  catalog="$home/model-catalog.json"
  configured="$(data_helper root-value "$scratch/original" model_catalog_json)" || return
  current_model="$(data_helper root-value "$scratch/original" model)" || return
  data_helper stage-model-config "$scratch/original/config.toml" "$scratch/config.toml" "$model" || return
  if [[ -n "$configured" ]]; then
    [[ "$configured" == "$catalog" ]] ||
      die "custom catalog for '$identity'; model settings were not applied to this identity"
    [[ -f "$catalog" && ! -L "$catalog" ]] ||
      die "catalog is not a regular, non-symlink file: $catalog"
    cp -p "$catalog" "$scratch/original/model-catalog.json" || return
    stage_ordered_catalog "$identity" "$scope" "$model" "$scratch" || return
  fi
  data_helper publish-model-files "$home" "$scratch" || return
  if [[ -n "$configured" ]]; then
    printf 'Updated picker order for %s.\n' "$identity"
  else
    printf 'Picker not created for %s; run: codex-home refresh-models %s\n' "$identity" "$identity"
  fi
  if [[ "$current_model" != "$model" ]]; then
    printf 'Updated %-9s to %s.\n' "$identity" "$model"
  else
    printf 'Current %-9s %s.\n' "$identity" "$model"
  fi
)

show_umgpt_defaults() {
  [[ $# -eq 0 ]] || die "usage: codex-home umgpt-defaults"
  local openai_model low_model repository_openai_model repository_low_model name home active_model
  openai_model="$(umgpt_default_model "openai-only")"
  low_model="$(umgpt_default_model "low-sensitivity")"
  repository_openai_model="$(umgpt_repository_default_model "openai-only")"
  repository_low_model="$(umgpt_repository_default_model "low-sensitivity")"
  printf 'Repository defaults: %s\n' "$UMGPT_REPOSITORY_MODELS_FILE"
  printf '  umgpt     %s\n' "$repository_openai_model"
  printf '  umgpt-low %s\n' "$repository_low_model"
  printf 'Local defaults: %s\n' "$UMGPT_MODELS_FILE"
  printf '  umgpt     %s  (U-M Azure OpenAI text only)\n' "$openai_model"
  printf '  umgpt-low %s  (LOW-SENSITIVITY DATA ONLY)\n' "$low_model"
  printf '\n%s\n' 'Preferred models (after the default; [] means automatic order):'
  printf '  umgpt_order = %s\n' "$(umgpt_models_file_value "$UMGPT_MODELS_FILE" umgpt_order)"
  printf '  umgpt_low_order = %s\n' "$(umgpt_models_file_value "$UMGPT_MODELS_FILE" umgpt_low_order)"
  for name in umgpt umgpt-low; do
    home="$(identity_home "$name")"
    if [[ -f "$home/config.toml" ]]; then
      active_model="$(data_helper root-value "$home" model)" || return
      printf 'Active default for %s: %s\n' "$name" "$active_model"
    fi
  done
  printf '\nEdit your settings: %s\n' "$UMGPT_MODELS_FILE"
  printf '%s\n' 'Apply defaults and picker order: codex-home apply-model-settings'
  printf '%s\n' 'List available choices: codex-home models umgpt / codex-home models umgpt-low'
  printf '%s\n' 'After a repository update, reset-umgpt-defaults adopts the repository values.'
}

set_umgpt_default() {
  [[ $# -eq 2 ]] || die "usage: codex-home set-umgpt-default umgpt|umgpt-low MODEL"
  local identity="$1"
  local model="$2"
  local scope openai_model low_model
  case "$identity" in
    umgpt) scope="openai-only" ;;
    umgpt-low) scope="low-sensitivity" ;;
    *) die "default identity must be 'umgpt' or 'umgpt-low'" ;;
  esac
  validate_umgpt_model "$scope" "$model"
  check_umgpt_default_identity "$identity" "$scope" "$model" || return
  openai_model="$(umgpt_default_model "openai-only")"
  low_model="$(umgpt_default_model "low-sensitivity")"
  if [[ "$scope" == "openai-only" ]]; then
    openai_model="$model"
  else
    low_model="$model"
  fi
  write_umgpt_models_file "$openai_model" "$low_model" \
    "$(umgpt_models_file_value "$UMGPT_MODELS_FILE" umgpt_order)" \
    "$(umgpt_models_file_value "$UMGPT_MODELS_FILE" umgpt_low_order)"
  printf 'Saved U-M GPT defaults in %s.\n' "$UMGPT_MODELS_FILE"
  sync_umgpt_default_identity "$identity" "$scope" "$model"
}

apply_umgpt_defaults() {
  [[ $# -eq 0 ]] || die "usage: codex-home apply-umgpt-defaults"
  # Read and validate both values before changing either identity.
  local openai_model low_model
  openai_model="$(umgpt_default_model "openai-only")" || return
  low_model="$(umgpt_default_model "low-sensitivity")" || return
  check_umgpt_default_identity "umgpt" "openai-only" "$openai_model" || return
  check_umgpt_default_identity "umgpt-low" "low-sensitivity" "$low_model" || return
  printf 'Applying U-M GPT model settings from %s.\n' "$UMGPT_MODELS_FILE"
  sync_umgpt_default_identity "umgpt" "openai-only" "$openai_model" || return
  sync_umgpt_default_identity "umgpt-low" "low-sensitivity" "$low_model" || return
  printf '%s\n' 'Restart Codex CLI; in VS Code run Developer: Reload Window, then start a new Codex chat.'
}

reset_umgpt_defaults() {
  [[ $# -eq 0 ]] || die "usage: codex-home reset-umgpt-defaults"
  local openai_model low_model
  openai_model="$(umgpt_repository_default_model "openai-only")"
  low_model="$(umgpt_repository_default_model "low-sensitivity")"
  check_umgpt_default_identity "umgpt" "openai-only" "$openai_model" || return
  check_umgpt_default_identity "umgpt-low" "low-sensitivity" "$low_model" || return
  write_umgpt_models_file "$openai_model" "$low_model" \
    "$(umgpt_models_file_value "$UMGPT_REPOSITORY_MODELS_FILE" umgpt_order)" \
    "$(umgpt_models_file_value "$UMGPT_REPOSITORY_MODELS_FILE" umgpt_low_order)"
  printf 'Reset local U-M GPT defaults from %s.\n' "$UMGPT_REPOSITORY_MODELS_FILE"
  sync_umgpt_default_identity "umgpt" "openai-only" "$openai_model" || return
  sync_umgpt_default_identity "umgpt-low" "low-sensitivity" "$low_model" || return
}

create_umgpt() {
  [[ $# -le 2 ]] || die "usage: codex-home create-umgpt [MODEL [NAME]]"
  local model explicit
  explicit=0
  if [[ $# -ge 1 ]]; then
    model="$1"
    explicit=1
  else
    model="$(umgpt_default_model "openai-only")"
  fi
  local name="${2:-umgpt}"
  validate_umgpt_model "openai-only" "$model"
  if [[ "$name" == "umgpt" && "$explicit" -eq 1 && -e "$UMGPT_MODELS_FILE" ]]; then
    umgpt_models_file_value "$UMGPT_MODELS_FILE" umgpt >/dev/null || return
  fi
  create_api_identity \
    "$name" \
    "$UMGPT_BASE_URL" \
    "$model" \
    "UMGPT_API_KEY" \
    "" \
    "umgpt-openai"
  if [[ "$name" == "umgpt" && "$explicit" -eq 1 ]]; then
    set_umgpt_default "umgpt" "$model"
  fi
  printf '%s\n' "Scope: U-M Azure OpenAI text models only. Use create-umgpt-low for other U-M models."
}

create_umgpt_low() {
  [[ $# -le 2 ]] || die "usage: codex-home create-umgpt-low [MODEL [NAME]]"
  local model explicit
  explicit=0
  if [[ $# -ge 1 ]]; then
    model="$1"
    explicit=1
  else
    model="$(umgpt_default_model "low-sensitivity")"
  fi
  local name="${2:-umgpt-low}"
  validate_umgpt_model "low-sensitivity" "$model"
  if [[ "$name" == "umgpt-low" && "$explicit" -eq 1 && -e "$UMGPT_MODELS_FILE" ]]; then
    umgpt_models_file_value "$UMGPT_MODELS_FILE" umgpt_low >/dev/null || return
  fi
  create_api_identity \
    "$name" \
    "$UMGPT_BASE_URL" \
    "$model" \
    "UMGPT_API_KEY" \
    "" \
    "umgpt-low"
  if [[ "$name" == "umgpt-low" && "$explicit" -eq 1 ]]; then
    set_umgpt_default "umgpt-low" "$model"
  fi
  printf '%s\n' "Scope: broader U-M text models; use only data approved for the selected model."
  printf '%s\n' "LOW-SENSITIVITY label: this is a local warning, not an institutional data classification."
}

set_umgpt_scope() {
  [[ $# -eq 2 ]] ||
    die "usage: codex-home set-umgpt-scope NAME openai-only|low-sensitivity"
  local name="$1"
  local scope="$2"
  local home kind base_url model next_kind
  ensure_identity "$name"
  home="$(identity_home "$name")"
  kind="$(identity_kind "$name")"
  is_api_key_kind "$kind" || die "identity '$name' is not an API-key identity"
  base_url="$(data_helper provider-value "$home" base_url)" || return
  [[ "${base_url%/}" == "$UMGPT_BASE_URL" ]] ||
    die "identity '$name' does not use the U-M GPT gateway"
  model="$(data_helper root-value "$home" model)" || return
  [[ -n "$model" ]] || die "could not find model in $home/config.toml"
  validate_umgpt_model "$scope" "$model"
  case "$scope" in
    openai-only) next_kind="umgpt-openai" ;;
    low-sensitivity) next_kind="umgpt-low" ;;
  esac
  write_identity_kind "$home" "$next_kind"
  printf "Set %s to %s.\n" "$name" "$(identity_label "$name")"
}

fetch_model_ids() {
  local base_url="$1"
  local api_key="$2"
  local url quoted_url quoted_header response ids status
  local -a curl_args=(-q --config -)

  validate_single_line "base URL" "$base_url" || return
  data_helper url "$base_url" || return
  command -v curl >/dev/null 2>&1 || die "curl is required for model discovery"
  command -v jq >/dev/null 2>&1 || die "jq is required for model discovery"
  url="${base_url%/}/models"
  quoted_url="$(curl_config_quote "$url")" || return
  quoted_header="$(curl_config_quote "Authorization: Bearer $api_key")" || return
  # Loopback development traffic must stay local even with a caller proxy.
  [[ "$base_url" != http://* ]] || curl_args+=(--noproxy '*')

  response="$(
    {
      printf 'url = %s\n' "$quoted_url"
      printf 'header = %s\n' "$quoted_header"
      printf '%s\n' 'silent' 'show-error' 'fail-with-body'
    } | data_helper client curl "${curl_args[@]}"
  )" || {
    status=$?
    if [[ -n "$response" ]]; then
      printf '%s\n' "$response" >&2
    fi
    die "model request failed (curl exit $status): $url"
  }

  if ! jq -e . >/dev/null 2>&1 <<< "$response"; then
    printf '%s\n' "$response" >&2
    die "provider returned a non-JSON model response: $url"
  fi

  ids="$(jq -r '
    if (.data? | type) == "array" then .data[]?
    elif (.models? | type) == "array" then .models[]?
    else empty
    end
    | if type == "string" then . else (.id? // .name? // empty) end
  ' <<< "$response")"

  if [[ -z "$ids" ]]; then
    jq . <<< "$response" >&2
    die "the response contained no model IDs"
  fi
  printf '%s\n' "$ids"
}

sort_umgpt_model_ids() {
  # Version order within families, not release chronology across vendors.
  # Use only the first numeric run so parameter counts (e.g. Llama's 17B)
  # do not become model versions. Compare components as integers, not decimals.
  jq -Rrsc '
    def family:
      ascii_downcase
      | if startswith("claude-") then [0, "claude"]
        elif startswith("gpt-") then [1, "gpt"]
        elif test("^o[0-9]") then [2, "o"]
        elif startswith("gemini-") then [3, "gemini"]
        else [4, split("-")[0]] end;
    def version:
      (match("[0-9]+([.-][0-9]+)*").string // "0")
      | [scan("[0-9]+") | tonumber];
    split("\n") | map(select(length > 0)) | unique
    | group_by(family)
    | map(group_by(version) | reverse | map(sort_by([ascii_downcase, .])) | add)
    | add // [] | .[]
  '
}

umgpt_model_order() {
  local scope="$1" file="$UMGPT_MODELS_FILE" key
  [[ -f "$file" ]] || file="$UMGPT_REPOSITORY_MODELS_FILE"
  case "$scope" in
    openai-only) key=umgpt_order ;;
    low-sensitivity) key=umgpt_low_order ;;
    *) printf '%s\n' '[]'; return ;;
  esac
  umgpt_models_file_value "$file" "$key"
}

ordered_umgpt_model_ids() {
  local scope="$1" selected="${2:-}" preferred
  preferred="$(umgpt_model_order "$scope")" || return
  sort_umgpt_model_ids | jq -Rrsc --arg selected "$selected" --argjson preferred "$preferred" '
    split("\n") | map(select(length > 0)) as $available
    | reduce ([$selected] + $preferred + $available)[] as $id
        ([]; if ($available | index($id)) != null and index($id) == null
             then . + [$id] else . end)
    | .[]
  '
}

snapshot_model_config() {
  local home="$1" scratch="$2"
  [[ -f "$home/config.toml" && ! -L "$home/config.toml" ]] ||
    die "config is not a regular, non-symlink file: $home/config.toml"
  mkdir "$scratch/original" || return
  cp -p "$home/config.toml" "$scratch/original/config.toml"
}

stage_ordered_catalog() {
  local name="$1" scope="$2" selected="$3" scratch="$4" ids
  local catalog="$scratch/original/model-catalog.json"
  jq -e --arg selected "$selected" '.models | type == "array" and
    any(.[]; .slug == $selected)' "$catalog" >/dev/null ||
    die "default '$selected' is not in the saved catalog; run: codex-home refresh-models $name --model $selected"
  ids="$(jq -r '.models[].slug' "$catalog")" || return
  ordered_umgpt_model_ids "$scope" "$selected" <<< "$ids" |
    jq -Rsc 'split("\n") | map(select(length > 0))' > "$scratch/ids.json" || return
  jq --slurpfile ids "$scratch/ids.json" '
    .models as $models
    | .models = ($ids[0] | to_entries | map(
        .key as $rank | .value as $id
        | ($models[] | select(.slug == $id)) + {priority: $rank}
      ))
  ' "$catalog" > "$scratch/model-catalog.json"
}

request_models() {
  local base_url="$1"
  local api_key="$2"
  local scope="${3:-all}"
  local url ids id shown hidden

  url="${base_url%/}/models"
  ids="$(fetch_model_ids "$base_url" "$api_key")"
  if [[ "$scope" == openai-only || "$scope" == low-sensitivity ]]; then
    ids="$(ordered_umgpt_model_ids "$scope" <<< "$ids")" || return
  fi

  case "$scope" in
    all) printf 'Available models from %s:\n' "$url" ;;
    openai-only) printf 'U-M Azure OpenAI text models allowed for this identity from %s:\n' "$url" ;;
    low-sensitivity) printf 'General text models available to this low-sensitivity identity from %s:\n' "$url" ;;
    *) die "unknown model-list scope: $scope" ;;
  esac
  shown=0
  hidden=0
  while IFS= read -r id; do
    if [[ "$scope" == "openai-only" ]] && ! is_umgpt_openai_text_model "$id"; then
      hidden=$((hidden + 1))
      continue
    fi
    if [[ "$scope" == "low-sensitivity" ]] && ! is_umgpt_general_text_model "$id"; then
      hidden=$((hidden + 1))
      continue
    fi
    printf '  %s\n' "$id"
    shown=$((shown + 1))
  done <<< "$ids"
  [[ "$shown" -gt 0 ]] || die "the response contained no models allowed by the '$scope' scope"
  if [[ "$hidden" -gt 0 ]]; then
    printf 'Hidden by this identity scope: %d model(s).\n' "$hidden"
  fi
}

probe_models() {
  [[ $# -eq 1 ]] || die "usage: codex-home probe-models BASE_URL"
  local base_url="$1"
  local secret
  validate_single_line "base URL" "$base_url"
  data_helper url "$base_url" || return
  [[ -t 0 ]] || die "probe-models requires an interactive terminal"

  prompt_secret "API key for $base_url: " secret || return
  [[ -n "$secret" ]] || die "key may not be empty"
  validate_single_line "API key" "$secret"
  request_models "$base_url" "$secret"
  unset secret
}

models_for_identity() {
  [[ $# -eq 1 ]] || die "usage: codex-home models NAME"
  local name="$1"
  local home key_env base_url api_key kind scope
  ensure_identity "$name"
  kind="$(identity_kind "$name")"
  is_api_key_kind "$kind" || die "identity '$name' is not an API-key identity"
  home="$(identity_home "$name")"
  key_env="$(api_key_env_for "$name")"
  base_url="$(data_helper provider-value "$home" base_url)" || return
  [[ -n "$base_url" ]] || die "could not find base_url in $home/config.toml"
  [[ -n "$key_env" ]] || die "could not find a supported stored-key configuration in $home/config.toml"
  api_key="$(data_helper secret "$home")" || return
  [[ -n "$api_key" ]] || die "$key_env is not set; run: codex-home set-key $name"
  scope="$(identity_umgpt_scope "$name" 2>/dev/null || printf '%s\n' "all")"
  if [[ "$scope" == "unset" ]]; then
    printf "Warning: U-M GPT identity '%s' has no model scope; run set-umgpt-scope before launching Codex.\n" "$name" >&2
    scope="all"
  fi
  request_models "$base_url" "$api_key" "$scope"
  unset api_key
}

refresh_models() (
  # A subshell keeps credentials, the temporary CODEX_HOME, and cleanup local.
  [[ $# -eq 1 || ( $# -eq 3 && "${2:-}" == --model ) ]] ||
    die "usage: codex-home refresh-models NAME [--model MODEL]"
  local name="$1" requested_model="${3:-}"
  local home scope key_env api_key ids id allowed="" scratch catalog configured_model saved_catalog
  ensure_identity "$name"
  scope="$(identity_umgpt_scope "$name" 2>/dev/null || true)"
  case "$scope" in
    openai-only|low-sensitivity) ;;
    *) die "refresh-models requires a scoped U-M GPT identity" ;;
  esac
  if [[ $# -eq 3 ]]; then validate_umgpt_model "$scope" "$requested_model"; fi
  validate_umgpt_identity_config "$name" skip-catalog || return
  command -v codex >/dev/null 2>&1 || die "codex is required to build the model picker catalog"
  home="$(cd "$(identity_home "$name")" && pwd -P)"
  catalog="$home/model-catalog.json"
  umask 077
  scratch="$(mktemp -d "$home/.model-catalog.XXXXXX")" || return
  trap '[[ -f "$scratch/retain" ]] || rm -rf -- "$scratch"' EXIT
  snapshot_model_config "$home" "$scratch" || return
  configured_model="$(data_helper root-value "$scratch/original" model)" || return
  # Preserve a user-managed catalog rather than silently replacing it.
  saved_catalog="$(data_helper root-value "$scratch/original" model_catalog_json)" || return
  [[ -z "$saved_catalog" || "$saved_catalog" == "$catalog" ]] ||
    die "config uses another model_catalog_json; remove that setting before refreshing"
  [[ ! -L "$catalog" && ( ! -e "$catalog" || -f "$catalog" ) ]] ||
    die "catalog is not a regular, non-symlink file: $catalog"
  if [[ -f "$catalog" ]]; then
    cp -p "$catalog" "$scratch/original/model-catalog.json" || return
  fi

  key_env="$(api_key_env_for "$name")"
  api_key="$(data_helper secret "$home")" || return
  [[ -n "$api_key" ]] || die "$key_env is not set; run: codex-home set-key $name"
  ids="$(fetch_model_ids "$UMGPT_BASE_URL" "$api_key")" || return
  unset api_key
  while IFS= read -r id; do
    is_model_id "$id" || die "the gateway returned an invalid model ID; catalog not updated"
    is_umgpt_general_text_model "$id" || continue
    if [[ "$scope" == openai-only ]]; then
      is_umgpt_openai_text_model "$id" || continue
    fi
    allowed+="$id"$'\n'
  done <<< "$ids"
  [[ -n "$allowed" ]] || die "the gateway returned no models allowed by this identity; catalog not updated"
  if [[ -n "$requested_model" ]]; then
    grep -Fxq -- "$requested_model" <<< "$allowed" ||
      die "requested model '$requested_model' is not advertised by the gateway; run: codex-home models $name"
    configured_model="$requested_model"
  elif ! grep -Fxq -- "$configured_model" <<< "$allowed"; then
    die "configured model '$configured_model' is not advertised by the gateway; run codex-home models $name, then codex-home refresh-models $name --model MODEL"
  fi

  # Use the installed client's metadata for known models without loading a
  # possibly stale catalog or project configuration, and without remote refresh.
  (cd "$scratch" && data_helper review "$name" "$scratch" codex debug models --bundled) > "$scratch/bundled.json" ||
    die "could not read the bundled Codex catalog; update Codex and retry"
  printf '%s' "$allowed" | ordered_umgpt_model_ids "$scope" "$configured_model" \
    | jq -Rsc 'split("\n") | map(select(length > 0))' > "$scratch/ids.json" || return
  # Codex marks the first catalog entry as isDefault in model/list, even when
  # config.toml selects another model. Pin the configured model before assigning
  # priorities; keep the remaining entries in family/version order.
  jq --slurpfile ids "$scratch/ids.json" '
    .models as $bundled
    | {models: ($ids[0] | to_entries | map(
        .key as $rank | .value as $id
        | ([$bundled[] | select(.slug == $id)][0] // {
            slug: $id,
            description: "U-M Toolkit text model; Codex compatibility unverified",
            base_instructions: "You are Codex, a coding assistant. Work with the user to complete their task. Read the relevant project instructions and inspect existing code before editing. Use the available tools to make focused changes and verify them. Preserve unrelated user changes. Explain the outcome, validation, and remaining limitations accurately.",
            default_reasoning_level: null,
            supported_reasoning_levels: [],
            shell_type: "shell_command",
            support_verbosity: false,
            default_verbosity: null,
            apply_patch_tool_type: null,
            default_reasoning_summary: "none",
            truncation_policy: {mode: "tokens", limit: 10000},
            experimental_supported_tools: [],
            input_modalities: ["text"]
          })
        | . + {display_name: $id, visibility: "list", supported_in_api: true,
               priority: $rank, upgrade: null, availability_nux: null}
      ))}
  ' "$scratch/bundled.json" > "$scratch/model-catalog.json" || die "could not build the model picker catalog"
  # Ask the installed Codex parser to check the generated catalog before either
  # live file changes. This performs no model inference or remote discovery.
  data_helper stage-model-config "$scratch/original/config.toml" "$scratch/config.toml" \
    "$configured_model" "$scratch/model-catalog.json" || return
  (cd "$scratch" && data_helper review "$name" "$scratch" codex debug models --bundled >/dev/null) ||
    die "Codex rejected the generated model catalog; existing files unchanged"

  data_helper stage-model-config "$scratch/original/config.toml" "$scratch/config.toml" \
    "$configured_model" "$catalog" || return
  data_helper publish-model-files "$home" "$scratch" || return
  if [[ -n "$requested_model" ]]; then printf 'Active default for %s: %s\n' "$name" "$configured_model"; fi
  printf 'Updated picker catalog for %s: %s model(s).\n' "$name" "$(jq '.models | length' "$catalog")"
  printf 'Catalog: %s\n' "$catalog"
  printf '%s\n' 'Restart Codex CLI; in VS Code run Developer: Reload Window, then start a new Codex chat.'
  printf '%s\n' 'Listing a model does not verify Responses API or tool-call compatibility.'
)

snapshot_umgpt_models() {
  [[ $# -le 2 ]] || die "usage: codex-home snapshot-umgpt-models [NAME [OUTPUT]]"
  local name="${1:-umgpt}"
  local output="${2:-$REPOSITORY_ROOT/docs/umgpt-models-snapshot.md}"
  local home scope key_env base_url api_key ids sorted_ids id snapshot_date
  local output_dir staged total openai_count low_count excluded_count
  local openai_match low_match note

  ensure_identity "$name"
  scope="$(identity_umgpt_scope "$name" 2>/dev/null || true)"
  case "$scope" in
    openai-only|low-sensitivity) ;;
    unset) die "U-M GPT identity '$name' has no model scope; classify it before generating a snapshot" ;;
    *) die "identity '$name' is not a scoped U-M GPT identity" ;;
  esac
  output_dir="$(dirname "$output")"
  [[ -d "$output_dir" ]] || die "snapshot output directory does not exist: $output_dir"
  [[ ! -L "$output" ]] || die "refusing to replace a symlinked snapshot: $output"
  [[ ! -e "$output" || -f "$output" ]] || die "snapshot output is not a regular file: $output"
  validate_umgpt_identity_config "$name" || return
  home="$(identity_home "$name")"
  key_env="$(api_key_env_for "$name")"
  base_url="$(data_helper provider-value "$home" base_url)" || return
  api_key="$(data_helper secret "$home")" || return
  [[ -n "$api_key" ]] || die "$key_env is not set; run: codex-home set-key $name"
  ids="$(fetch_model_ids "$base_url" "$api_key")"
  unset api_key

  while IFS= read -r id; do
    is_model_id "$id" || die "the gateway returned an invalid model ID; snapshot not updated"
  done <<< "$ids"
  sorted_ids="$(printf '%s\n' "$ids" | LC_ALL=C sort -u)"

  snapshot_date="${CODEX_UMGPT_SNAPSHOT_DATE:-$(date +%Y-%m-%d)}"
  [[ "$snapshot_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] ||
    die "CODEX_UMGPT_SNAPSHOT_DATE must use YYYY-MM-DD"

  total=0
  openai_count=0
  low_count=0
  excluded_count=0
  while IFS= read -r id; do
    total=$((total + 1))
    if is_umgpt_openai_text_model "$id"; then
      openai_count=$((openai_count + 1))
    fi
    if is_umgpt_general_text_model "$id"; then
      low_count=$((low_count + 1))
    else
      excluded_count=$((excluded_count + 1))
    fi
  done <<< "$sorted_ids"

  staged="$(mktemp "$output_dir/.umgpt-models-snapshot.XXXXXX")" ||
    die "could not stage snapshot beside $output"

  if ! {
    printf '%s\n\n' '# U-M GPT model snapshot'
    printf -- '- **Generated:** %s\n' "$snapshot_date"
    printf -- '- **Source:** `%s/models`\n' "${base_url%/}"
    printf -- '- **Advertised to identity:** `%s`\n' "$name"
    printf -- '- **Advertised IDs:** %d\n' "$total"
    printf -- '- **Matches `umgpt`:** %d\n' "$openai_count"
    printf -- '- **Matches `umgpt-low`:** %d\n' "$low_count"
    printf -- '- **Excluded from both text scopes:** %d\n\n' "$excluded_count"
    printf '%s\n\n' '> The IDs reflect the key used for this listing. "Matches" means the ID passes the local scope filter. Run `codex-home models NAME` for live results. Verify model compatibility and data approval separately.'
    printf '%s\n' '| Model ID | `umgpt` rule | `umgpt-low` rule | Local classification |'
    printf '%s\n' '|---|---|---|---|'
    while IFS= read -r id; do
      if is_umgpt_openai_text_model "$id"; then
        openai_match="Matches"
        low_match="Matches"
        note="GPT/o-series ID without image/embedding"
      elif is_umgpt_general_text_model "$id"; then
        openai_match="Does not match"
        low_match="Matches"
        note="Other ID without image/embedding"
      else
        openai_match="Does not match"
        low_match="Does not match"
        note="ID contains image or embedding"
      fi
      printf '| `%s` | %s | %s | %s |\n' "$id" "$openai_match" "$low_match" "$note"
    done <<< "$sorted_ids"
  } > "$staged"; then
    rm -f "$staged"
    die "could not write snapshot: $output"
  fi
  chmod 644 "$staged"
  if ! mv "$staged" "$output"; then
    rm -f "$staged"
    die "could not install snapshot: $output"
  fi
  printf 'Updated U-M GPT model snapshot: %s\n' "$output"
}

validate_umgpt_identity_config() {
  local name="$1"
  local scope home config catalog
  scope="$(identity_umgpt_scope "$name" 2>/dev/null || true)"
  [[ -n "$scope" ]] || return 0
  [[ "$scope" != "unset" ]] ||
    die "U-M GPT identity '$name' has no model scope; run: codex-home set-umgpt-scope $name openai-only"
  home="$(identity_home "$name")"
  config="$home/config.toml"
  data_helper umgpt-identity "$home" "$name" "$scope" || return
  catalog="$(data_helper root-value "$home" model_catalog_json)" || return
  if [[ "${2:-}" != skip-catalog && "$scope" == "openai-only" && -n "$catalog" ]]; then
    local id
    [[ "$catalog" == "$(cd "$home" && pwd -P)/model-catalog.json" ]] ||
      die "U-M GPT Azure OpenAI identities require a scope-filtered catalog from refresh-models"
    command -v jq >/dev/null 2>&1 || die "jq is required to validate the model catalog"
    jq -e '.models | type == "array" and length > 0 and all(.[];
      type == "object" and (.slug | type == "string" and
        test("^[a-zA-Z0-9][a-zA-Z0-9._:/@+-]*$") and (contains("\n") | not)))' "$catalog" >/dev/null ||
      die "invalid model catalog; run: codex-home refresh-models $name"
    while IFS= read -r id; do
      validate_umgpt_model "$scope" "$id"
    done < <(jq -r '.models[].slug' "$catalog")
  fi
}

validate_project_umgpt_model() {
  local name="$1"
  local project_abs="$2"
  local scope project_config cursor
  scope="$(identity_umgpt_scope "$name" 2>/dev/null || true)"
  [[ -n "$scope" && "$scope" != "unset" ]] || return 0
  cursor="$(cd "$project_abs" && pwd -P)"
  while :; do
    project_config="$cursor/.codex/config.toml"
    if [[ -e "$project_config" ]]; then
      data_helper project "$project_config" "$scope" || return
    fi
    [[ "$cursor" != / ]] || break
    cursor="$(dirname "$cursor")"
  done
}

umgpt_config_override_is_blocked() {
  local scope="$1"
  local override="$2"
  if data_helper override "$scope" "$override"; then return 1; else return 0; fi
}

prepare_umgpt_codex_args() {
  local name="$1"
  local scope="$2"
  shift 2
  local home configured_model arg value feature end_options model_seen
  home="$(identity_home "$name")"
  configured_model="$(data_helper root-value "$home" model)" || return
  UMGPT_SCOPED_MODEL="$configured_model"
  UMGPT_SCOPED_ARGS=()
  end_options=0
  model_seen=0

  while [[ $# -gt 0 ]]; do
    arg="$1"
    shift
    if [[ "$end_options" == 1 ]]; then
      UMGPT_SCOPED_ARGS+=("$arg")
      continue
    fi
    case "$arg" in
      --)
        end_options=1
        UMGPT_SCOPED_ARGS+=("$arg")
        ;;
      -m|--model)
        [[ $# -gt 0 ]] || die "$arg requires a model ID"
        [[ "$model_seen" == 0 ]] || die "specify the model only once"
        UMGPT_SCOPED_MODEL="$1"
        model_seen=1
        shift
        ;;
      -C|--cd)
        UMGPT_SCOPED_ARGS+=("$arg" "$1")
        shift
        ;;
      --model=*)
        [[ "$model_seen" == 0 ]] || die "specify the model only once"
        UMGPT_SCOPED_MODEL="${arg#--model=}"
        model_seen=1
        ;;
      -m?*)
        [[ "$model_seen" == 0 ]] || die "specify the model only once"
        value="${arg#-m}"
        UMGPT_SCOPED_MODEL="${value#=}"
        model_seen=1
        ;;
      -c|--config)
        [[ $# -gt 0 ]] || die "$arg requires key=value"
        value="$1"
        shift
        if umgpt_config_override_is_blocked "$scope" "$value"; then
          die "configuration override can bypass the U-M GPT '$scope' model scope; use --model with an allowed model instead"
        fi
        UMGPT_SCOPED_ARGS+=("$arg" "$value")
        ;;
      --config=*)
        value="${arg#--config=}"
        if umgpt_config_override_is_blocked "$scope" "$value"; then
          die "configuration override can bypass the U-M GPT '$scope' model scope; use --model with an allowed model instead"
        fi
        UMGPT_SCOPED_ARGS+=("$arg")
        ;;
      -c?*)
        value="${arg#-c}"
        value="${value#=}"
        if umgpt_config_override_is_blocked "$scope" "$value"; then
          die "configuration override can bypass the U-M GPT '$scope' model scope; use --model with an allowed model instead"
        fi
        UMGPT_SCOPED_ARGS+=("$arg")
        ;;
      -p|--profile|--oss|--local-provider|--remote|--ignore-user-config)
        die "'$arg' can bypass the U-M GPT '$scope' model scope; use a separate identity"
        ;;
      --profile=*|--local-provider=*|--remote=*|-p?*)
        die "'$arg' can bypass the U-M GPT '$scope' model scope; use a separate identity"
        ;;
      --enable)
        [[ $# -gt 0 ]] || die "--enable requires a feature name"
        feature="$1"
        shift
        if [[ "$scope" == "openai-only" &&
          ( "$feature" == "api_key_model_discovery" || "$feature" == "remote_models" ) ]]; then
          die "feature '$feature' can bypass the U-M GPT Azure OpenAI model scope"
        fi
        UMGPT_SCOPED_ARGS+=("$arg" "$feature")
        ;;
      --enable=*)
        feature="${arg#--enable=}"
        if [[ "$scope" == "openai-only" &&
          ( "$feature" == "api_key_model_discovery" || "$feature" == "remote_models" ) ]]; then
          die "feature '$feature' can bypass the U-M GPT Azure OpenAI model scope"
        fi
        UMGPT_SCOPED_ARGS+=("$arg")
        ;;
      *) UMGPT_SCOPED_ARGS+=("$arg") ;;
    esac
  done
  validate_umgpt_model "$scope" "$UMGPT_SCOPED_MODEL"
}

