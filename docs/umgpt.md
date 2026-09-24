# U-M GPT API setup

[Setup steps](#1-obtain-an-api-key) · [Data permissions](#check-data-permissions-first) · [Scope details](#exact-local-filtering-rules) · [Troubleshooting](troubleshooting.md#accounts-and-models)

**Already connected?** Go to [Model settings and comparison](../MODELS.md) to
change defaults, reorder your picker, or compare prices, context windows, and
benchmarks. This page covers connection and compatibility setup.

Use this guide if you have access to the U-M GPT Toolkit API and approval to
use it for your work. A Toolkit API key is separate from a ChatGPT login. The
helper uses the U-M gateway at:

```text
https://api.toolkit.umgpt.umich.edu/v1
```

After [installing prerequisites and cloning the repository](../INSTALLATION.md#1-install-prerequisites)
(Installation steps 1–3), run `./bin/codex-home` examples from the clone
directory; bare `codex-home` assumes it is on PATH.

Choose the identity whose scope fits your work. Use separate identities when
you need both scopes:

| Identity | Model scope | Intended use |
|---|---|---|
| `umgpt` | GPT and o-series text IDs through U-M's Azure OpenAI-backed service | Normal U-M GPT work, subject to current approval for the model, workflow, and data |
| `umgpt-low` | Other general text models as well as OpenAI text models | Models with tighter data restrictions, with a **LOW-SENSITIVITY DATA ONLY** warning |

Both scopes reject image-generation and embedding model IDs because they are
not general Codex text models. The names are local guardrails, not U-M data
classifications or evidence of institutional approval. See
[how the U-M gateway differs from direct OpenAI access](#what-azure-openai-means-here).

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

Query the gateway with a hidden key prompt:

```bash
./bin/codex-home probe-models https://api.toolkit.umgpt.umich.edu/v1
```

This prints the IDs advertised to your key without storing it. Match your
choice to the scope above; [exact filtering rules](#exact-local-filtering-rules)
are listed below. A model list does not establish tool-call compatibility.
You will test that in step 6.

## 3. Choose your models

To start with the saved defaults, inspect them:

```bash
./bin/codex-home model-settings
```

This works before creating an identity. For a new setup, it creates your personal
settings file from the [repository template](../config/umgpt-models.toml).
If standard identities already exist, initialization imports their valid
configured defaults. Confirm the defaults appear in the live list from step 2.
To choose another model, [compare models](../MODELS.md#compare-models), then
pass its exact ID when creating the identity in step 4.

After setup, use [Change defaults and order](../MODELS.md#change-defaults-and-order)
to edit saved choices and arrange the picker. Repository updates preserve
your personal settings and existing identities' configured models.

<a id="4-create-the-two-identities"></a>

## 4. Create the identities you need

Run the pair of commands for each identity you need. They use the saved
defaults and prompt for its key:

```bash
./bin/codex-home create-umgpt
./bin/codex-home set-key umgpt

./bin/codex-home create-umgpt-low
./bin/codex-home set-key umgpt-low
```

Each key is stored in that identity's `.env` file with owner-only permissions
(mode `600`). To choose a different initial model, replace the corresponding
creation command above with one of these examples, using an ID from step 2:

```bash
./bin/codex-home create-umgpt gpt-6-sol
./bin/codex-home create-umgpt-low claude-opus-5-5
```

For the standard names, an explicit model also becomes the saved default.
If an identity already exists, [change its settings](../MODELS.md#change-defaults-and-order)
instead of creating it again. For identities created before scopes were added,
follow [Upgrade an older identity](#upgrade-an-older-identity).

<a id="5-select-a-model-for-one-session"></a>

## 5. Populate the model picker

Refresh the picker for each identity you created:

```bash
./bin/codex-home refresh-models umgpt
./bin/codex-home refresh-models umgpt-low
```

Restart the CLI, or run **Developer: Reload Window** in VS Code and start a
new Codex chat. The picker should show models within that identity's scope,
with its saved default first. The default itself stays unchanged.

`probe-models` and `models` only print IDs; `refresh-models` updates the picker.
For a one-session override, catalog details, or a failed refresh, see the
[model reference](model-reference.md#other-model-settings).

## 6. Validate compatibility

Inspect and diagnose each identity you created, replacing `umgpt` with
`umgpt-low` for the broader scope:

```bash
./bin/codex-home show umgpt
./bin/codex-home doctor umgpt
./bin/codex-home models umgpt
```

Then run the [tool-call smoke test](api-providers.md#validate-compatibility),
replacing `research-api` with the identity you are testing. Use non-sensitive
test content; the request may incur charges. Repeat for each model you plan
to use. A model listing or plain-text response does not establish full Codex
compatibility.

[Verify the selected identity](commands.md#check-the-selected-identity) before
using it with project data. For failures, start with
[API and model troubleshooting](troubleshooting.md#accounts-and-models).

## 7. Assign an identity to a project

Continue with [project setup](projects-vscode.md#generate-project-files), using
`umgpt` or `umgpt-low` as the identity. That guide covers generating the files,
reviewing them, approving `.envrc`, and opening the project.

The normal U-M identity uses a navy VS Code status bar; the low-sensitivity
identity uses red. Start a new Codex chat and
[verify the selected identity](commands.md#check-the-selected-identity).

## What “Azure OpenAI” means here

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

## Exact local filtering rules

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

## Upgrade an older identity

To classify an older U-M identity created before model scopes were added:

```bash
./bin/codex-home set-umgpt-scope umgpt openai-only
```

The `openai-only` scope token means U-M's Azure OpenAI-backed Toolkit lane; it
does not authorize or configure a direct OpenAI endpoint.

Use `low-sensitivity` instead only for an older identity intentionally using a
broader text model. An unclassified legacy U-M identity is blocked from helper
launches until it is assigned a scope.

## Provider display names

New U-M identities use `U-M GPT Toolkit (umgpt)` or
`U-M GPT Toolkit (umgpt-low; LOW-SENSITIVITY DATA ONLY)` as the provider
display name. Custom identity names replace `umgpt` or `umgpt-low` in those
labels, so multiple keys remain distinguishable.

For an existing identity, edit only the `name` value in its provider table in
`$CODEX_HOME/config.toml`. For example, in
`~/.codex-homes/umgpt/config.toml`:

```toml
[model_providers.umgpt]
name = "U-M GPT Toolkit (umgpt)"
# Keep the existing base_url, env_key, and wire_api entries here.
```

The [`name` field is Codex's provider display name](https://learn.chatgpt.com/docs/config-file/config-reference).
Keep `model_provider = "umgpt"` and `[model_providers.umgpt]` unchanged:
the helper uses the identity name as the provider ID and checks it at launch.
Restart Codex to use the updated configuration. Display varies by client and
version; CLI `/status` may still show the provider ID. Existing configuration
files are not rewritten automatically when you update this repository.

## Multiple U-M keys

Create a named identity for each additional key and specify its model:

```bash
./bin/codex-home create-umgpt gpt-6-sol umgpt-study-a
./bin/codex-home set-key umgpt-study-a

./bin/codex-home create-umgpt-low claude-sonnet-5 umgpt-low-study-b
./bin/codex-home set-key umgpt-low-study-b
```

The local defaults file applies only when a creation command omits its model.
`set-umgpt-default` and `apply-model-settings` update the standard identities
named `umgpt` and `umgpt-low`; named identities retain their own configured
models. `reset-umgpt-defaults` likewise updates only those two standard
identities after copying the repository recommendations into the local file.

See [Troubleshooting](troubleshooting.md) for HTTP 401, missing-model, and
Responses API errors.
