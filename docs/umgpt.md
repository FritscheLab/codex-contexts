# U-M GPT API setup

Use this guide if you have access to the U-M GPT Toolkit API and approval to
use it for your work. A Toolkit API key is separate from a ChatGPT login. The
helper uses the U-M gateway at:

```text
https://api.toolkit.umgpt.umich.edu/v1
```

After [installing prerequisites and cloning the repository](../INSTALLATION.md#1-install-prerequisites)
(Installation steps 1–3), run `./bin/codex-home` examples from the clone
directory; bare `codex-home` assumes it is on PATH.

Two deliberately separate identities reduce accidental model switching:

| Identity | Model scope | Intended use |
|---|---|---|
| `umgpt` | GPT and o-series text IDs through U-M's Azure OpenAI-backed service | Normal U-M GPT work, subject to current approval for the model, workflow, and data |
| `umgpt-low` | Other general text models as well as OpenAI text models | Models with tighter data restrictions, with a **LOW-SENSITIVITY DATA ONLY** warning |

Both scopes reject image-generation and embedding model IDs because they are
not general Codex text models. The names are local guardrails, not U-M data
classifications or evidence of institutional approval.

### What “Azure OpenAI” means here

[ITS describes U-M GPT](https://its.umich.edu/computing/ai) as providing
hosted Azure OpenAI models alongside U-M-hosted open-source models. The
[ITS AI Services FAQ](https://its.umich.edu/computing/ai/faq) says the U-M AI
environment is housed in a private Microsoft Azure cloud, and the
[ITS AI Services privacy notice](https://safecomputing.umich.edu/viziblue/ai-data)
says Microsoft Azure Services supports delivery under contractual privacy and
security controls.

The official [Codex via U-M GPT Toolkit](https://its.umich.edu/computing/ai/codex-gpt-toolkit)
page confirms that Codex model requests go through the Toolkit gateway and do
not require a separate OpenAI API account.

Accordingly, `umgpt` means GPT and o-series text IDs reached through the exact
U-M Toolkit gateway above. It does **not** mean a direct OpenAI Platform API
key, a personal ChatGPT account, or arbitrary software from OpenAI. U-M's
[guidance for direct OpenAI products](https://teamdynamix.umich.edu/TDClient/30/Portal/KB/Article/12163/Can-t-Connect-My-OpenAI-Account-Product-to-My-U-M-Google-or-Microsoft-365-Account)
states that U-M has no binding DPA or BAA with OpenAI for those products. A
`gpt-*` model name outside the U-M gateway therefore does not inherit the
Toolkit's approval or protections.

## Check data permissions first

The [U-M ITS AI Services entry in the Sensitive Data Guide](https://safecomputing.umich.edu/dataguide/service/75)
(which may require U-M sign-in) is the place to check current data permissions.
The public [U-M GPT model descriptions](https://its.umich.edu/computing/ai/gpt-in-depth#models)
list Claude Sonnet 5, Claude Opus 5, and Llama 4 Maverick as not authorized for
protected health information (PHI). This does not establish approval for other
models.

Rules and available models can change. Recheck the current guide and your
unit's requirements before each new use case. The
[ITS FAQ](https://its.umich.edu/computing/ai/faq) describes the service as
approved for moderately sensitive data, but that does not make every model or
workflow interchangeable. Before using PHI, confirm that the selected model
and this Codex CLI/API workflow are both approved; general permission for the
service is not enough. Do not use AI output as the basis for patient care or
clinical support decisions.

## 1. Obtain an API key

Create a key through the [U-M GPT Toolkit self-service portal](https://toolkit.umgpt.umich.edu/).
Store it with `set-key`, not in shell commands, project files, VS Code settings,
issues, or chat.

### Costs and spending controls

[U-M GPT web chat is offered at no cost](https://its.umich.edu/computing/ai/pricing),
but the Toolkit API used here is billed by usage. The
[Toolkit portal](https://toolkit.umgpt.umich.edu/) provides quotas and billing
information, and [ITS says Toolkit keys must be renewed annually](https://its.umich.edu/computing/ai/gpt-toolkit-in-depth).
Check the [current ITS Toolkit pricing table](https://its.umich.edu/computing/ai/pricing)
before choosing a model.

[ChatGPT/Codex plan credits](https://learn.chatgpt.com/docs/pricing) do not
cover Toolkit API calls. A Codex task can make multiple requests, so check the
portal's **Total Spend** rather than assuming one fixed cost per task.

## 2. Discover current model IDs

Before creating an identity, query the gateway with a hidden key prompt:

```bash
./bin/codex-home probe-models https://api.toolkit.umgpt.umich.edu/v1
```

This prints the current IDs from `/v1/models` without storing the key. Once an
identity exists, use its stored key and scope-aware list:

```bash
./bin/codex-home models umgpt
./bin/codex-home models umgpt-low
```

`models umgpt` shows GPT and o-series text IDs from U-M's Azure OpenAI lane.
`models umgpt-low` shows general text IDs across vendors. Both hide
image-generation and embedding IDs. This live query is the easiest way to
accommodate models added by U-M over time; no static list in this repository
is authoritative.

### Exact local filtering rules

The helper applies these literal, name-based rules to each model ID returned
by the gateway:

- `umgpt` matches the case-sensitive shell patterns `gpt-*` or `o[0-9]*`,
  after rejecting any ID containing `image` or `embedding` (the exclusion is
  case-insensitive).
- `umgpt-low` matches every ID that does not contain `image` or `embedding`.

Therefore, `umgpt-low` is a superset: GPT and o-series text IDs match both
scopes, while model IDs such as Claude or Gemini match only `umgpt-low`. The
rules inspect the ID string; they do not use provider metadata and do not
establish the model's owner, capabilities, or approval status. The normal
identity is additionally pinned to the exact U-M Toolkit gateway URL.

### Dated model snapshot

The repository includes a generated
[U-M GPT model snapshot](umgpt-models-snapshot.md) so the catalog observed on
one date can be reviewed without a live query. A maintainer with a configured,
scoped identity and stored key can refresh it with:

```bash
./bin/codex-home snapshot-umgpt-models umgpt docs/umgpt-models-snapshot.md
```

The command accepts `snapshot-umgpt-models [NAME [OUTPUT]]`; its defaults are
`umgpt` and `docs/umgpt-models-snapshot.md`. It records the raw `/models`
response visible to that identity, then shows which IDs match each local rule.
The result is dated, credential-specific, and informational. It is not a
compatibility or institutional-approval list, and runtime validation never
reads it. Use `codex-home models NAME` when you need the live, scope-filtered
result for your own credential.

The [Toolkit in-depth guide](https://its.umich.edu/computing/ai/gpt-toolkit-in-depth)
warns that newly listed models may still be under testing. A listed model may
not implement the Responses API, streaming, and tool calls required by Codex,
and listing does not automatically approve it for sensitive data.

## 3. Understand recommendations, defaults, and the live catalog

The model settings are intentionally separated:

| Source | Purpose |
|---|---|
| [`config/umgpt-models.toml`](../config/umgpt-models.toml) | Version-controlled recommendations maintained by this repository |
| `~/.codex-homes/umgpt-models.toml` | Your local defaults for the standard `umgpt` and `umgpt-low` identities |
| [`docs/umgpt-models-snapshot.md`](umgpt-models-snapshot.md) | Dated, generated observation retained for review; never used at runtime |
| `codex-home models umgpt` / `codex-home models umgpt-low` | Current scope-filtered model IDs queried live from the U-M gateway |

The repository file is the easy-to-find place for maintainers to update the
two recommended IDs. It is not a complete or authoritative model catalog.
Pulling a repository update does not silently replace a user's local choices.

Show the repository recommendations beside your local defaults with:

```bash
./bin/codex-home umgpt-defaults
```

On a new setup, the local file starts from the checked-in recommendations. By
default it is `~/.codex-homes/umgpt-models.toml` and currently contains:

```toml
umgpt = "gpt-6-sol"
umgpt_low = "claude-sonnet-5"
```

When upgrading an existing standard identity, the helper preserves its valid
configured model as the initial default instead of silently changing it.

The local file contains model IDs only, never the API key. Update one local
default and its existing standard identity with:

```bash
./bin/codex-home set-umgpt-default umgpt gpt-6-sol
./bin/codex-home set-umgpt-default umgpt-low claude-sonnet-5
```

Alternatively, edit the TOML values and validate/apply both in one step:

```bash
./bin/codex-home apply-umgpt-defaults
```

After pulling a repository update, explicitly adopt both checked-in
recommendations and update any existing standard identities with:

```bash
./bin/codex-home reset-umgpt-defaults
```

This overwrites both values in the local defaults file. It does not update
additional named identities such as `umgpt-study-a`.

The helper accepts only GPT and o-series text IDs for `umgpt`, while also
pinning that identity to the U-M Toolkit URL. It refuses image or embedding
IDs for either default. Set `CODEX_UMGPT_MODELS_FILE` if the defaults file must
live elsewhere. Keep it outside a shared repository if different users need
different defaults.

## 4. Create the two identities

With the defaults above, no model argument is needed:

```bash
./bin/codex-home create-umgpt
./bin/codex-home set-key umgpt

./bin/codex-home create-umgpt-low
./bin/codex-home set-key umgpt-low
```

The key is stored separately in each identity's `.env` file with mode `600`.
An explicit model can still be supplied during creation; for a standard
identity, it also becomes the saved default:

```bash
./bin/codex-home create-umgpt gpt-6-sol
./bin/codex-home create-umgpt-low claude-opus-5-5
```

To classify an older U-M identity created before model scopes were added:

```bash
./bin/codex-home set-umgpt-scope umgpt openai-only
```

The `openai-only` scope token means U-M's Azure OpenAI-backed Toolkit lane; it
does not authorize or configure a direct OpenAI endpoint.

Use `low-sensitivity` instead only for an older identity intentionally using a
broader text model. An unclassified legacy U-M identity is blocked from helper
launches until it is assigned a scope.

New identities also use a `U-M GPT Toolkit` provider display name, including
the identity name and a low-sensitivity warning where applicable. To update
an existing identity's configured label, follow
[Provider display names](api-providers.md#provider-display-names).

## 5. Select a model for one session

Pass an exact ID without changing the saved default:

```bash
./bin/codex-home run umgpt -m gpt-5.6-terra
./bin/codex-home run umgpt-low -m claude-opus-5-5
```

The normal identity rejects Claude, Gemini, Llama, and other IDs outside the
U-M Azure OpenAI lane. The low-sensitivity identity permits general text
models and prints a prominent warning at launch.

Codex's `/model` selector may not contain every model exposed by the custom
U-M gateway. `probe-models` and `models` do not alter that selector. Use the
exact ID with `-m`, or update the default as shown above. The helper does not
install a custom `model_catalog_json`, which would add another static catalog
to maintain. See
the [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference#model_catalog_json).

## 6. Validate compatibility

```bash
./bin/codex-home show umgpt
./bin/codex-home doctor umgpt
./bin/codex-home models umgpt

./bin/codex-home show umgpt-low
./bin/codex-home doctor umgpt-low
./bin/codex-home models umgpt-low
```

Then run the tool-call smoke test in the
[API provider validation guide](api-providers.md#validate-compatibility) with
non-sensitive test content. A successful model listing or plain-text response
does not establish full Codex compatibility.
Then [check the selected identity](commands.md#check-the-selected-identity)
before assigning it to a project.

## 7. Assign an identity to a project

```bash
./bin/codex-home project umgpt "/path/to/project"
```

Review the generated `.envrc` and `.vscode/<folder-name>.code-workspace` before
approval. Then run:

```bash
direnv allow "/path/to/project"
./bin/codex-home vscode umgpt "/path/to/project"
```

Use `umgpt-low` in both helper commands for the broader identity. The normal
identity uses a navy status bar; the low-sensitivity identity uses red. Start
a new Codex chat and follow the [CLI or VS Code verification steps](commands.md#check-the-selected-identity)
to check the selected home, provider configuration, authentication, and model.

## Guardrail boundaries

For helper-launched sessions, `codex-home run` validates model overrides and
blocks command-line configuration switches that could change the provider or
model scope. The VS Code launcher validates the identity and a project's
top-level `.codex/config.toml` model setting.

This is an accidental-misuse guardrail, not a security boundary. Running
`codex` directly, manually editing identity files, changing unrecognized Codex
configuration paths, or continuing an already-open session can bypass the
helper. Always start a new session after changing identities and
[verify the selected identity](commands.md#check-the-selected-identity) before
providing data.

## Multiple U-M keys

Create a named identity for each additional key and specify its model:

```bash
./bin/codex-home create-umgpt gpt-6-sol umgpt-study-a
./bin/codex-home set-key umgpt-study-a

./bin/codex-home create-umgpt-low claude-sonnet-5 umgpt-low-study-b
./bin/codex-home set-key umgpt-low-study-b
```

The local defaults file applies only when a creation command omits its model.
`set-umgpt-default` and `apply-umgpt-defaults` update the standard identities
named `umgpt` and `umgpt-low`; named identities retain their own configured
models. `reset-umgpt-defaults` likewise updates only those two standard
identities after copying the repository recommendations into the local file.

See [Troubleshooting](troubleshooting.md) for HTTP 401, missing-model, and
Responses API errors.
