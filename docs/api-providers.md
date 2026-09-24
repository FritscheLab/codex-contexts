# API providers

[Choose a provider](#support-matrix) · [Generic API](#generic-bearer-token-gateway) · [OpenAI](#openai-platform-api-key) · [Azure](#direct-azure-openai) · [Test tool calls](#validate-compatibility)

Use a separate identity for each API provider or key. The helper can configure
Responses-compatible APIs, direct Azure endpoints, and the U-M GPT gateway.
Other providers supported by Codex need manual setup.

After [installing prerequisites and cloning the repository](../INSTALLATION.md#1-install-prerequisites)
(Installation steps 1–3), run `./bin/codex-home` examples from the clone
directory; bare `codex-home` assumes it is on PATH.

## Support matrix

| Provider | Codex support | Managed by this helper | Setup |
|---|---|---|---|
| ChatGPT sign-in | Built-in `openai` provider | Yes | `create-subscription` |
| Responses-compatible bearer-token API | Custom provider | Yes | `create-api` |
| Direct Azure OpenAI Responses endpoint | Custom provider | Yes | `create-azure` |
| U-M GPT, Azure OpenAI text-model scope | U-M gateway; permits GPT and o-series text IDs on U-M's Azure OpenAI-backed path | Yes | `create-umgpt` |
| U-M GPT, broader text-model scope | Custom provider; permits other vendors and shows a low-sensitivity warning | Yes | `create-umgpt-low` |
| Ollama or LM Studio | Built-in local OSS mode | No | Configure Codex `--oss` or `oss_provider` manually |
| Amazon Bedrock | Built-in `amazon-bedrock` provider for supported OpenAI models | No | Configure Codex and AWS authentication manually |
| Command-backed bearer token | Custom provider authentication | Manual only | Edit the identity's `config.toml` |

For managed providers, the helper writes the configuration and helps you store
credentials. Manual setups may also work in a separate home, but are not
covered by this repository's tests.

## What `create-api` supports

`create-api` creates an identity for a custom provider that:

- accepts a bearer token supplied through an environment variable;
- exposes an OpenAI Responses-compatible endpoint at the configured base URL;
- supports the selected model ID through that endpoint.

The model can come from OpenAI or another vendor. For U-M GPT, prefer the
[U-M setup commands](umgpt.md) instead of a generic `create-api` identity. Test each
selected model with Codex's Responses requests and tool calls. U-M GPT requires
its own API key and bills Toolkit usage separately; see the
[cost and quota guidance](umgpt.md#costs-and-spending-controls).

`responses` is the only supported custom-provider `wire_api` value. A service
described as “OpenAI compatible” may support only Chat Completions, which this
helper cannot translate. AWS and local-model authentication also need their
own setup, described below.

Put provider and authentication settings in `$CODEX_HOME/config.toml`. Codex
ignores provider redirection in a project's `.codex/config.toml`, so the helper
selects a separate home for each provider.

## U-M GPT model scopes

For the U-M Toolkit gateway, use [U-M GPT setup](umgpt.md). It covers API keys,
costs, initial model selection, and compatibility checks for these identities:

- `umgpt`: GPT and o-series text IDs through U-M's Azure OpenAI-backed gateway.
- `umgpt-low`: broader text-model access, with a **LOW-SENSITIVITY DATA ONLY** warning.

Use the scope appropriate for your approved model, workflow, and data. Scope
labels are local safeguards; check [U-M data permissions](umgpt.md#check-data-permissions-first)
before use. After setup, use [Model settings and comparison](../MODELS.md) to
change defaults and picker order.

### Provider display names

For an existing U-M identity's label, follow
[Provider display names](umgpt.md#provider-display-names) in the U-M guide.

## Generic bearer-token gateway

```bash
./bin/codex-home create-api research-api \
  https://api.example.org/v1 \
  MODEL_ID \
  RESEARCH_API_KEY
./bin/codex-home set-key research-api
./bin/codex-home doctor research-api
./bin/codex-home models research-api
```

The identity name also becomes the provider ID. Names such as `openai`,
`ollama`, `lmstudio`, and `amazon-bedrock` are reserved for built-in providers.
Choose a name such as `openai-lab` or `local-router`.

`models` calls `<base-url>/models` with bearer authentication. If your provider
does not offer that route, use its documented model ID and test a Codex request.
Model listing alone does not test Codex compatibility.

## Multiple keys for the same service

Create a home per key. The environment-variable names may be distinct:

```bash
./bin/codex-home create-api lab-a https://api.example.org/v1 MODEL LAB_A_KEY
./bin/codex-home set-key lab-a

./bin/codex-home create-api lab-b https://api.example.org/v1 MODEL LAB_B_KEY
./bin/codex-home set-key lab-b
```

You can also reuse one variable name: the helper loads the selected identity's
`.env`. It does not clear unrelated variables or credentials inherited from
your shell. Different names can make debugging outside `direnv` easier.

## OpenAI Platform API key

For an OpenAI Platform key, use `create-api`:

```bash
./bin/codex-home create-api openai-project-a \
  https://api.openai.com/v1 \
  MODEL_ID \
  OPENAI_PROJECT_A_API_KEY
./bin/codex-home set-key openai-project-a
```

Use a model available to that API project. API keys and billing are separate
from a ChatGPT subscription. For a direct OpenAI
Platform key, check [current OpenAI API pricing](https://developers.openai.com/api/docs/pricing).
Gateways set their own rates; for U-M GPT Toolkit, use the
[ITS pricing and quota guidance](umgpt.md#costs-and-spending-controls).

Codex also supports its built-in `openai` provider and `openai_base_url` for
routers that preserve OpenAI authentication. This repository uses explicit
custom provider IDs so you can check each identity's URL, model, and key setting.

## Direct Azure OpenAI

Use `create-azure` only for the direct Azure endpoint shape:

```bash
./bin/codex-home create-azure azure-lab \
  https://YOUR_PROJECT_NAME.openai.azure.com/openai \
  DEPLOYMENT_OR_MODEL_NAME \
  AZURE_OPENAI_API_KEY \
  API_VERSION
./bin/codex-home set-key azure-lab
```

This adds:

```toml
query_params = { api-version = "API_VERSION" }
wire_api = "responses"
```

Get the API version and deployment or model name from your Azure resource
administrator. Also confirm the endpoint and authentication headers: some
Azure setups use a different format.

For the U-M GPT gateway, use `create-umgpt` or `create-umgpt-low` rather than a
direct Azure identity.

## Upstream capabilities not managed here

### Ollama and LM Studio

Codex can run against Ollama or LM Studio in local OSS mode using `--oss`,
`--local-provider`, or the `oss_provider` setting. This helper does not create
or validate those configurations. Follow the
[Codex OSS-mode guidance](https://learn.chatgpt.com/docs/config-file/config-advanced#oss-mode-local-providers)
and confirm that the chosen local model supports the tools your work requires.

### Amazon Bedrock

Codex includes the `amazon-bedrock` provider for supported OpenAI models served
through Amazon Bedrock. It uses AWS-native authentication and region settings,
not the generic bearer-token configuration generated by `create-api`. Follow
the official
[Amazon Bedrock setup guide](https://learn.chatgpt.com/docs/amazon-bedrock)
and configure it manually inside the intended Codex home.

Do not use `create-api amazon-bedrock ...`; that name belongs to Codex's
built-in provider, and this repository does not manage its AWS credentials.

## Providers requiring extra headers

Create the identity, then edit its user-level config:

```text
~/.codex-homes/<identity>/config.toml
```

Codex supports static and environment-populated headers:

```toml
[model_providers.corp-gateway]
name = "Corporate gateway"
base_url = "https://gateway.example.org/v1"
env_key = "CORP_API_KEY"
wire_api = "responses"
http_headers = { "X-Client" = "codex" }
env_http_headers = { "X-Project" = "CORP_PROJECT_ID" }
```

Do not put a secret value in `http_headers`; use `env_http_headers` and load the
referenced variable privately. Run `codex-home doctor NAME` after manual edits.

## Command-backed bearer tokens

Codex can run a credential helper when tokens are short-lived:

```toml
[model_providers.corp-gateway]
name = "Corporate gateway"
base_url = "https://gateway.example.org/v1"
wire_api = "responses"

[model_providers.corp-gateway.auth]
command = "/usr/local/bin/fetch-codex-token"
args = ["--audience", "codex"]
timeout_ms = 5000
refresh_interval_ms = 300000
```

Configure this manually, without `env_key` or `codex-home set-key`. The command
must print only the token to standard output and protect any credentials it
uses to obtain that token.

## Validate compatibility

Before using a provider for your work, check that Codex can call tools with
your chosen model. A model listing or plain text reply is not enough. Confirm:

1. The base URL and authentication format match the provider's documentation.
2. The credential can access the configured model or deployment ID.
3. The gateway implements streaming OpenAI Responses requests.
4. The selected model can execute the tool calls used by Codex.
5. Your institution approves the provider's data handling, retention, network,
   and billing arrangements for your work.

Test tool calls in a temporary Git repository. This example asks Codex to
create a small marker file; replace
`research-api` and the repository path as needed:

```bash
(
  set -eu
  CODEX_CONTEXTS="$HOME/Developer/codex-contexts"
  SMOKE_DIR="$(mktemp -d)"
  printf 'Smoke-test directory: %s\n' "$SMOKE_DIR"
  git -C "$SMOKE_DIR" init --quiet
  cd "$SMOKE_DIR"
  "$CODEX_CONTEXTS/bin/codex-home" run research-api exec \
    --ephemeral \
    --sandbox workspace-write \
    "Create codex-smoke-test.txt containing exactly OK, using a tool."
  test "$(cat codex-smoke-test.txt)" = "OK"
  printf 'Tool-call smoke test passed: %s\n' "$SMOKE_DIR"
)
```

This request may incur provider charges. Keep research data out of the test.
Inspect the temporary directory, then delete it when you are done.

After validation, [check the selected identity](commands.md#check-the-selected-identity)
and [assign it to a project](projects-vscode.md).

References:

- [Codex custom model providers](https://learn.chatgpt.com/docs/config-file/config-advanced#custom-model-providers)
- [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
- [Codex OSS mode](https://learn.chatgpt.com/docs/config-file/config-advanced#oss-mode-local-providers)
- [Codex with Amazon Bedrock](https://learn.chatgpt.com/docs/amazon-bedrock)
