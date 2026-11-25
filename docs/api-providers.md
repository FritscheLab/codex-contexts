# API providers

[Choose a provider](#support-matrix) | [Create an identity](#generic-bearer-token-gateway) | [Azure](#direct-azure-openai) | [Test tools](#validate-compatibility) | [Provider errors](#provider-errors)

Use one identity per provider or key. `create-api` configures a bearer-token
API that supports streaming OpenAI Responses requests. A service offering
only Chat Completions needs a different integration; this helper does not
translate between protocols.

These commands assume `codex-home` is on `PATH`. [Installation](../INSTALLATION.md)

## Support matrix

| Your access | Setup |
|---|---|
| ChatGPT account/workspace | [Subscription identity](subscriptions.md) |
| Responses-compatible bearer-token API | [`create-api`](#generic-bearer-token-gateway) |
| Direct Azure OpenAI endpoint | [`create-azure`](#direct-azure-openai) |
| U-M GPT Toolkit key | [U-M setup and model scopes](umgpt.md) |
| Ollama, LM Studio, or Amazon Bedrock | [Manual upstream setup](#upstream-capabilities-not-managed-here) |
| Extra headers or short-lived tokens | [Manual authentication settings](#providers-requiring-extra-headers) |

## Generic bearer-token gateway

Replace the URL, model ID, and key-variable name with your provider's values.
Create the identity, then inspect the provider and base URL before saving the key.

```bash
codex-home create-api research-api \
  https://api.example.org/v1 MODEL_ID RESEARCH_API_KEY
codex-home show research-api
```

Once the URL matches your provider, enter the key at the hidden prompt. This
writes a plaintext key file in the private identity home and replaces any key
previously stored there. [Credential storage and rotation](security.md#where-data-lives)

```bash
codex-home set-key research-api
```

The identity name becomes its provider ID. `openai`, `ollama`, `lmstudio`, and
`amazon-bedrock` are reserved; use a label such as `openai-lab`.

For another key, repeat these commands with another identity name. Variable
names can be reused across homes. New identities use Codex's native
`auth.command` to read that home's private `api-key.env` as data. The selected key is
kept out of the editor and command environments. Use `codex-home run NAME`
for the launcher checks.

See [provider checks](security.md#provider-checks) for HTTPS and local-loopback
HTTP rules, [environment forwarding](security.md#environment-forwarding) for
extra variables, and [credential boundaries](security.md#secret-exposure-boundaries)
for same-user access limits. Test the identity [below](#validate-compatibility)
before using project data.

## OpenAI Platform API key

Use the generic commands with `https://api.openai.com/v1` and a model available
to that API project. API billing is separate from a ChatGPT subscription;
check [OpenAI API pricing](https://developers.openai.com/api/docs/pricing).

The helper uses a distinct custom provider ID rather than the built-in
`openai` ID, so each identity's endpoint and key setting stay explicit.
For Toolkit access, use [U-M setup](umgpt.md) and its billing guidance.

## Direct Azure OpenAI

Use the API version and deployment/model name supplied by your Azure resource
administrator:

```bash
codex-home create-azure azure-lab \
  https://YOUR_PROJECT_NAME.openai.azure.com/openai \
  DEPLOYMENT_OR_MODEL_NAME AZURE_OPENAI_API_KEY API_VERSION
codex-home show azure-lab
```

Confirm the base URL against your Azure resource before entering the key.

```bash
codex-home set-key azure-lab
```

This adds `query_params = { api-version = "API_VERSION" }` and
`wire_api = "responses"`. Confirm the endpoint and authentication headers
with your administrator; Azure configurations vary. U-M's gateway uses the
[U-M commands](umgpt.md), rather than this direct Azure variant.

## Providers requiring extra headers

After creation, edit the existing `[model_providers.NAME]` table in
`$CODEX_HOME/config.toml`. For example:

```toml
http_headers = { "X-Client" = "codex" }
env_http_headers = { "X-Project" = "CORP_PROJECT_ID" }
```

Keep secrets out of static `http_headers`. Supply private values through the
referenced environment variables and explicitly forward their names:

```bash
CODEX_CONTEXTS_ENV_ALLOW='CORP_PROJECT_ID' codex-home doctor research-api
```

Use the same forwarding choice for normal launches, then verify a tool call.
[Supported configuration fields](https://learn.chatgpt.com/docs/config-file/config-reference) | [Compatibility test](#validate-compatibility)

## Command-backed bearer tokens

For short-lived tokens, manually add an authentication helper to the selected
provider table:

```toml
[model_providers.research-api.auth]
command = "/usr/local/bin/fetch-codex-token"
args = ["--audience", "codex"]
timeout_ms = 5000
refresh_interval_ms = 300000
```

Replace the generated `auth` value with this table, omit `env_key`, and do not
use `set-key` for this variant. The command must
print only the token to standard output and protect its own credentials.
Explicitly forward any variables it needs; see
[environment forwarding](security.md#environment-forwarding).

## Upstream capabilities not managed here

Local OSS mode and Bedrock authentication need manual configuration in the
intended identity home:

- [Ollama and LM Studio](https://learn.chatgpt.com/docs/config-file/config-advanced#oss-mode-local-providers)
  use Codex's local-provider settings.
- [Amazon Bedrock](https://learn.chatgpt.com/docs/amazon-bedrock) uses AWS-native
  authentication and region settings. Do not create a custom provider named
  `amazon-bedrock`; forward required AWS variables explicitly.

Use Codex's provider instructions to configure and test these routes.
[Codex custom providers](https://learn.chatgpt.com/docs/config-file/config-advanced#custom-model-providers)

## Validate compatibility

Use this check for generic, Azure, and U-M API identities. Verify the endpoint,
authentication format, and model/deployment ID against the provider's
documentation, and confirm approval for your data, retention, network, and
billing arrangements.

Inspect the saved configuration and run diagnostics:

```bash
codex-home show research-api
codex-home doctor research-api
codex-home models research-api
```

`models` queries `<base-url>/models`; that discovery route is optional.
A model listing or text reply does not establish streaming Responses and
tool-call compatibility. Test the chosen model in an empty Git repository:

```bash
(
  set -eu
  SMOKE_DIR="$(mktemp -d)"
  printf 'Smoke-test directory: %s\n' "$SMOKE_DIR"
  git -C "$SMOKE_DIR" init --quiet
  cd "$SMOKE_DIR"
  codex-home run research-api exec \
    --ephemeral --sandbox workspace-write \
    "Create codex-smoke-test.txt containing exactly OK, using a tool."
  test "$(cat codex-smoke-test.txt)" = "OK"
)
```

Replace `research-api` with your identity. This request may incur
charges; keep sensitive data out of the test. Inspect the temporary directory,
then delete it when finished. Repeat for each model you intend to use.

Then [verify the selected identity](commands.md#check-the-selected-identity)
and [assign it to a project](projects-vscode.md).

## Provider errors

| Symptom | Check or repair |
|---|---|
| HTTP 401/403 | Check the key's project, expiry/revocation, and required authentication format. [Replace the stored key](security.md#rotation-and-revocation) if needed; connect to a VPN when the provider requires it. |
| `/models` returns 404 | Discovery is optional. Use a documented model ID and run the tool-call test above. |
| `/responses` or tool calls fail | Confirm support for streaming Responses requests and Codex tools. Chat Completions compatibility alone is insufficient. |
| Model/deployment not found | Use the exact ID advertised by the gateway or provider; for Azure, also check the deployment name and API version. |
