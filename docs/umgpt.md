# Optional: U-M GPT API setup

Use this guide if you have access to the U-M GPT Toolkit API and approval to
use it for your work. The gateway offers several model families, including
Claude and GPT. You will need a Toolkit API key; a ChatGPT login does not give
you access.

`create-umgpt` uses this gateway:

```text
https://api.toolkit.umgpt.umich.edu/v1
```

The helper configures the OpenAI Responses protocol, including for Claude
models. Test the model's support for Responses and tool calls in step 4.
Keep the gateway URL as shown; add Azure's `api-version` parameter only if
U-M's documentation requires it.

## Check data permissions for the selected model

The [U-M ITS AI Services entry in the Sensitive Data Guide](https://safecomputing.umich.edu/dataguide/service/75)
(which may require U-M sign-in) lists which data types the service permits.
For protected health information (PHI), there is a model-specific restriction:
**all U-M GPT Claude models and Llama 4 Maverick are not authorized for PHI**.
A model switch can change which data you may use with the same identity. The
[U-M GPT model descriptions](https://its.umich.edu/computing/ai/gpt-in-depth#models)
also mark the listed Claude models and Llama 4 Maverick as not authorized for
PHI.

The guide requires Information Assurance consultation for Social Security
Numbers and student loan application information regulated by GLBA. It lists
attorney-client privileged information, CUI, PCI information, export-controlled
research, FISMA data, and sensitive identifiable human subject research as not
permitted. Review the current guide and your unit's requirements for every
data type before use. Before using PHI, confirm with U-M that both the selected
model and this Codex CLI/API workflow are approved. General permission for the
service is not enough.
Do not use AI output as the basis for patient care or clinical support decisions.

## 1. Obtain an API key

Create a key through the [U-M GPT Toolkit self-service portal](https://toolkit.umgpt.umich.edu/).
ITS says faculty and staff can create keys with
an approved U-M Shortcode; eligible student employees need a faculty or staff
sponsor. Store the key with `set-key` in step 3. Keep it out of shell commands,
project files, VS Code settings, issues, and chat.

### Costs and spending controls

[U-M GPT web chat is offered at no cost](https://its.umich.edu/computing/ai/pricing),
but **the Toolkit API used here is billed by usage**. ITS bills
Toolkit usage monthly to the associated Shortcode. The
[Toolkit portal](https://toolkit.umgpt.umich.edu/) lets key owners set monthly
quotas and view the billing dashboard. [ITS says Toolkit keys must be renewed
annually](https://its.umich.edu/computing/ai/gpt-toolkit-in-depth). Check the
[current ITS Toolkit pricing table](https://its.umich.edu/computing/ai/pricing)
before choosing a model; rates can change.

[ChatGPT/Codex plans have their own usage limits and credits](https://learn.chatgpt.com/docs/pricing).
Those credits do not cover Toolkit API calls. Their price depends on the plan
or agreement, so there is no fixed conversion from ChatGPT credits to Toolkit
dollars.

Selected ITS rates as of September 18, 2026, in USD per 1 million tokens:

| Gateway model ID | Prompt tokens | Completion tokens |
|---|---:|---:|
| `claude-haiku-4-5` | $1.00 | $5.00 |
| `claude-sonnet-5` | $2.00 | $10.00 |
| `claude-opus-5` | $5.00 | $25.00 |
| `gpt-5.6-luna` | $0.20 | $1.20 |
| `gpt-5.6-sol` | $5.00 | $30.00 |

Estimate cost from the prompt and completion token counts using the rates
above. For example, at the listed Sonnet 5 rates,
100,000 prompt tokens plus 20,000 completion tokens would cost about $0.40.
A Codex task can make multiple model requests, so a single task has no fixed
price. Check the portal's **Total Spend** for actual billed usage. ITS notes
that its **Total Tokens** figure combines input, cache-read, and cache-write
tokens billed at different rates, so it may not reproduce Total Spend by
simple multiplication. See the [ITS AI Services FAQ](https://its.umich.edu/computing/ai/faq)
for that dashboard limitation.

## 2. Discover and choose a default model

Before creating the identity, use the hidden terminal prompt:

```bash
./bin/codex-home probe-models https://api.toolkit.umgpt.umich.edu/v1
```

The command prompts for your key and lists IDs from `/v1/models`. It passes
the key to `curl` through standard input and does not store it. It does not
create an identity or add models to Codex's model selector.

If model listing is unavailable for your key, get the exact model ID from
the portal or U-M support and continue with that value.
Do not guess an Azure deployment or public OpenAI model name.

The [U-M GPT model descriptions](https://its.umich.edu/computing/ai/gpt-in-depth#models)
show that Claude Sonnet and Opus are offered in the U-M GPT interface. As of
September 18, 2026, U-M lists Sonnet 5 and Opus 5 as available only to faculty
and full-time staff. Web chat and API access may differ, so check which models
your key can access.

### Example model list (2026-09-17)

For reference, `/v1/models` returned these 38 IDs for one authorized key on
September 17, 2026. Run the command yourself to see what is available now:

<details>
<summary>Show the model IDs returned on 2026-09-17</summary>

```text
Llama-4-Maverick-17B-128E-Instruct-FP8
Llama-4-Scout-17B-16E-Instruct
claude-haiku-4-5
claude-opus-4-6
claude-opus-4-7
claude-opus-4-8
claude-opus-5
claude-sonnet-4-6
claude-sonnet-5
claude-fable-5-1
gemini-3.5-flash
gemini-3.6-flash
gemini-3.7-flash
gemini-3.8-flash
gemini-3-flash-preview
gemini-3.1-flash-image-preview
gpt-4.1
gpt-5.6-luna
gpt-5.6-sol
gpt-5.6-terra
gpt-6-astra
gpt-4.1-mini
gpt-4.1-nano
gpt-4o
gpt-4o-mini
gpt-5
gpt-5-mini
gpt-5.1
gpt-5.2
gpt-5.4
gpt-5.5
gpt-image-1.5
gpt-image-2
o1
o3
kimi-k2.5
text-embedding-3-small
text-embedding-3-large
```

</details>

Availability varies by key and date. This list includes image and embedding
models as well as coding models; avoid IDs containing `gpt-image`,
`image-preview`, or `text-embedding` for general Codex use. Test every model
you choose in step 4. A listed model has not necessarily been tested with
Codex or approved for PHI.

## 3. Create the identity and store the key

Replace `MODEL_ID` with a value returned or documented by U-M:

```bash
./bin/codex-home create-umgpt MODEL_ID
./bin/codex-home set-key umgpt
```

The generated config is equivalent to:

```toml
model = "MODEL_ID"
model_provider = "umgpt"

[model_providers.umgpt]
name = "Codex identity: umgpt"
base_url = "https://api.toolkit.umgpt.umich.edu/v1"
env_key = "UMGPT_API_KEY"
wire_api = "responses"
```

The key is stored at `~/.codex-homes/umgpt/.env` with mode `600` and is not
written into that TOML file.

To use a different model for one session, pass its exact gateway ID at launch:

```bash
./bin/codex-home run umgpt -m OTHER_MODEL_ID
```

Within Codex, `/model` opens the model selector. It may not list every U-M
gateway model, and `probe-models` does not update it. Use the command above
when an ID is missing. See the
[Codex CLI guide](https://learn.chatgpt.com/docs/codex/cli) and
[configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference#model_catalog_json).

## 4. Validate configuration and compatibility

```bash
./bin/codex-home show umgpt
./bin/codex-home doctor umgpt
./bin/codex-home models umgpt
```

Check the results:

- `show` confirms the local paths and whether a key is stored or loaded.
- `doctor` validates the configuration and reports its runtime checks.
- `models` confirms bearer authentication and model-list access.

These commands do not test whether Codex can call tools with the selected
model. Before using the identity in a real project, run the tool-call test in the
[API provider validation guide](api-providers.md#validate-compatibility),
using `umgpt` as the identity name. The test may incur a small provider charge;
do not include research data or other sensitive content.

If `/models` succeeds but the smoke test fails on a `/responses` route, ask U-M
whether the selected model and gateway credential support the Responses API
and Codex tool calls. A gateway that supports only Chat Completions is not
sufficient for this custom-provider configuration.

## 5. Assign it to a project and VS Code

```bash
./bin/codex-home project umgpt "/path/to/project"
direnv allow "/path/to/project"
./bin/codex-home vscode umgpt "/path/to/project"
```

For a project already in Git, setup keeps the generated files out of commits
through `.git/info/exclude`. Review `.envrc` before running `direnv allow`.

The window title includes `[CODEX: UMGPT]` and its status bar is orange. In a
new integrated terminal, check the selected identity:

```bash
codex-home current
```

## Multiple U-M keys

Create a separate identity for each key:

```bash
./bin/codex-home create-umgpt MODEL_ID umgpt-study-a
./bin/codex-home set-key umgpt-study-a

./bin/codex-home create-umgpt MODEL_ID umgpt-study-b
./bin/codex-home set-key umgpt-study-b
```

Each home stores its own `UMGPT_API_KEY`. `direnv` loads the key from the
project's selected home, so you do not need a global key in your shell settings.

See [Troubleshooting](troubleshooting.md) for HTTP 401, missing model, and
Responses API errors.
