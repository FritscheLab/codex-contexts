# Model reference

[← Compare models and change settings](../MODELS.md)

- **Comparison details:** [Prices and limits](#prices-and-limits) · [Benchmark notes](#benchmark-notes)
- **Picker help:** [Available models](#available-models) · [Other settings](#other-model-settings) · [Catalog behavior](#how-picker-catalogs-work) · [Refresh and recovery](#refresh-and-recovery)

## Prices and limits

Checked **2026-09-24**. The [comparison table](../MODELS.md#compare-models) contains
input/output prices, context sizes, and performance. The additional values and
primary sources below complete that table. All prices are USD per million tokens.

| Model | Cached input | Maximum output | Price source | Limit source |
|---|---:|---:|---|---|
| GPT-6 Luna | $0.01 | 128,000 | [OpenAI](https://developers.openai.com/api/docs/pricing) | [Model](https://developers.openai.com/api/docs/models/gpt-6-luna) |
| GPT-6 Sol | $0.20 | 128,000 | [OpenAI](https://developers.openai.com/api/docs/pricing) | [Model](https://developers.openai.com/api/docs/models/gpt-6-sol) |
| GPT-6 Astra | $1.00 | 128,000 | [OpenAI](https://developers.openai.com/api/docs/pricing) | [Model](https://developers.openai.com/api/docs/models/gpt-6-astra) |
| Claude Haiku 4.5 | $0.10 | 64K | [Anthropic](https://platform.claude.com/docs/en/about-claude/pricing) | [Models](https://platform.claude.com/docs/en/models/overview) |
| Claude Sonnet 5 | $0.20 | 128K | [Anthropic](https://platform.claude.com/docs/en/about-claude/pricing) | [Models](https://platform.claude.com/docs/en/models/overview) |
| Claude Opus 5.5 | $0.20 base | 128K | [Anthropic](https://platform.claude.com/docs/en/about-claude/pricing) | [Models](https://platform.claude.com/docs/en/models/overview) |
| Claude Fable 5.1 | $0.25 | 128K | [Anthropic](https://platform.claude.com/docs/en/about-claude/pricing) | [Models](https://platform.claude.com/docs/en/models/overview) |
| Gemini 3.8 Flash | $0.075 | 65,536 | [Google](https://ai.google.dev/gemini-api/docs/pricing) | [Model](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash) |
| DeepSeek V4 Flash 0731 | $0.03 | Not verified | [Together AI](https://www.together.ai/pricing) | [Model](https://www.together.ai/models/deepseek-v4-flash-0731) |
| Kimi K3 | $0.30 | Not verified | [Together AI](https://www.together.ai/pricing) | [Kimi guide](https://platform.kimi.ai/docs/guide/kimi-k3-quickstart) |
| Kimi K2.5 | $0.10 | Not verified | [Novita](https://novita.ai/console/pricing-console) | [Moonshot](https://huggingface.co/moonshotai/Kimi-K2.5) |
| Llama 4 Maverick FP8 | Not verified | Not verified | [DeepInfra](https://deepinfra.com/meta-llama/Llama-4-Maverick-17B-128E-Instruct-FP8) | Same endpoint |
| Llama 4 Scout | Not verified | Not verified | [DeepInfra](https://deepinfra.com/meta-llama/Llama-4-Scout-17B-16E-Instruct) | Same endpoint |

### Pricing basis

Use standard, global provider prices where available. For open models, use
the named host's published rate. This does not identify U-M's deployment or
guarantee its bill. The comparison applies only the observed **Opus 5.5
input/output adjustment of 10%**. U-M does not publish cache prices; no cache
surcharge or blanket family fee is inferred.

<details>
<summary>Evidence: provider prices versus posted U-M prices</summary>

This compares base provider prices with U-M's published input/output prices;
a difference does not establish its cause. Source rates: [U-M](https://its.umich.edu/computing/ai/pricing),
[Anthropic](https://platform.claude.com/docs/en/about-claude/pricing), and the
named hosting sources in the table above.

| Model | Provider input / output | U-M input / output | Observed difference |
|---|---:|---:|---|
| Haiku 4.5 | $1 / $5 | $1 / $5 | None |
| Sonnet 5 | $2 / $10 | $2 / $10 | None |
| Opus 5.5 | $4 / $20 | $4.40 / $22 | +10% on both |
| Fable 5.1 | $10 / $50 | $10 / $50 | None |
| Kimi K2.5 (Novita) | $0.60 / $3 | $0.60 / $3 | None |
| Llama 4 Maverick (DeepInfra) | $0.20 / $0.80 | $0.35 / $1.41 | +75% / +76.25%; different hosting rates |
| Llama 4 Scout (DeepInfra) | $0.10 / $0.30 | $0.20 / $0.78 | +100% / +160%; different hosting rates |
| DeepSeek V4 Flash 0731, Kimi K3 | See comparison table | Not listed | Cannot infer an adjustment |

Use the [Toolkit portal](https://toolkit.umgpt.umich.edu/) for actual charges.

</details>

### Special rates and context limits

- **GPT-6:** the displayed prices apply through 272K input tokens. Above that,
  input/cache prices double and output prices rise 50% for the full request.
  Short-context cache writes cost $0.125 / $2.50 / $12.50 for Luna / Sol / Astra.
  All three have 1,050,000 context, capped at 922,000 input and 128,000 output.
  See the OpenAI sources above.
- **Claude:** five-minute cache writes cost $1.25 / $2.50 / $5 / $12.50 for
  Haiku / Sonnet / Opus / Fable; one-hour writes cost $2 / $4 / $8 / $20.
  These are unadjusted Anthropic base prices. See the Anthropic sources above.
- **Gemini 3.8 Flash:** displayed rates apply through 2026-12-31 and double on
  2027-01-01 in Google's schedule; this does not establish future U-M rates.
  Cache storage is extra. The input limit is 1,048,576 tokens, separately from
  maximum output. See the Google sources above.
- **DeepSeek:** Together lists the exact `0731` model. DeepSeek's own Flash
  alias now routes to V4.1, so its current price is not substituted for 0731.
  [Alias changes](https://api-docs.deepseek.com/updates/).
- **Llama:** the selected DeepInfra endpoints provide 1,048,576 context for
  Maverick FP8 and 327,680 for Scout. Scout's native 10M model context is not
  that host's serving limit. See the endpoint sources above.

Published limits can differ from U-M's route. Instructions, tools, and history
also consume context in Codex. These reference values do not change the
helper's conservative runtime metadata; see [catalog behavior](#how-picker-catalogs-work).

<details>
<summary>Azure OpenAI deployment-specific pricing</summary>

The [Azure pricing page](https://azure.microsoft.com/en-us/pricing/details/azure-openai/)
directs readers to Microsoft's GPT-6 announcement while Sol and Luna prices
are being added to its main table. Its **Global Standard, short-context** rates
match OpenAI, checked 2026-09-24.

US Data Zone Standard rates are 10% higher and EU Data Zone Standard rates
20% higher for these GPT-6 models. The source also lists cache-write and
long-context rates. These list prices do not establish the deployment type or
rate billed by U-M. [Microsoft's deployment-specific price table](https://azure.microsoft.com/en-us/blog/gpt-6-astra-sol-and-luna-for-production-agents-in-microsoft-foundry/).

</details>

## Benchmark notes

All capability scores use **Artificial Analysis Intelligence Index v4.3.2**,
a composite of 10 evaluations. It is not a percentage accuracy. See the
[evaluator's methodology](https://artificialanalysis.ai/methodology/intelligence-benchmarking)
and the model-specific links in the [comparison table](../MODELS.md#compare-models).

| Models | Evaluator setting |
|---|---|
| GPT-6 Luna, Sol, Astra; Gemini 3.8 Flash | Medium |
| Sonnet 5 | Adaptive, medium in the table; high also shown in the plot |
| Opus 5.5; Fable 5.1 | Adaptive, medium, evaluator's default fallback |
| Haiku 4.5; Kimi K2.5 | Reasoning enabled |
| DeepSeek V4 Flash 0731; Kimi K3 | Max |
| Llama 4 Maverick; Llama 4 Scout | Non-reasoning |

These are evaluation settings, not settings the helper applies. Kimi K2.5 and
both Llama index scores are **estimates pending independent evaluation** on
this index. The evaluator marks DeepSeek 0731 and Kimi K2.5 deprecated, limiting
ongoing performance updates; U-M still lists those IDs. Llama's score describes
the model, not U-M's particular quantized deployment.

Output speed measures delivery after generation starts, excluding the initial
wait. Artificial Analysis uses first-party APIs where available and otherwise
provider medians. These are not U-M measurements and need not describe the
host used for pricing. [Speed methodology](https://artificialanalysis.ai/methodology).

### Update the comparison

[Source data](data/model-benchmarks.csv) records exact IDs, evaluation settings,
status, base prices, verification dates, and source links. Adjustments are
separate fields: `price_adjustment_percent` and `adjustment_source`. The
[plot script](build-model-benchmarks.py) multiplies base input/output prices by
`1 + adjustment / 100`; it never fetches or imputes missing data.

Update the dated CSV and corresponding comparison values, then regenerate the
PNG and editable SVG from the repository root with Matplotlib installed:

```bash
python3 docs/build-model-benchmarks.py
```

## Available models

The live `umgpt-low` query returned **38 text models on 2026-09-24**: 9 Claude,
17 GPT, 2 o-series, 5 Gemini, 1 DeepSeek, 2 Kimi, and 2 Llama. All 19 GPT/o-series
models also appear in `umgpt`. Six image/embedding IDs are filtered out.
The comparison covers 13 models; omission does not imply unavailability or
poor performance.

[Browse the complete dated catalog and scope classifications](umgpt-models-snapshot.md).
For the current IDs available to your credential, run:

```bash
./bin/codex-home models umgpt
./bin/codex-home models umgpt-low
```

These commands query the gateway and print IDs; they do not update the picker.
See the [local filtering rules](umgpt.md#exact-local-filtering-rules) for scope details.

## Other model settings

The [main guide](../MODELS.md#change-defaults-and-order) covers editing and applying
settings. These options address less common cases.

| Need | Action |
|---|---|
| Change one default quickly | `./bin/codex-home set-umgpt-default umgpt MODEL` (or `umgpt-low`); retains favorite order |
| Use a model for one CLI session | `./bin/codex-home run NAME -m MODEL`; use an exact ID within that identity's scope; saved choices stay unchanged |
| Reset order only | Set both order arrays to `[]`, then apply |
| Adopt repository defaults and order | `./bin/codex-home reset-umgpt-defaults`; **overwrites personal choices**, then reload |
| Change the maintainer template | Edit [`config/umgpt-models.toml`](../config/umgpt-models.toml); users' saved settings remain intact |
| Use another settings file | Set `CODEX_UMGPT_MODELS_FILE` to its path |

Additional named identities retain their configured defaults. Favorites apply
by scope on their next `refresh-models NAME`; `apply-model-settings` updates
only the standard `umgpt` and `umgpt-low` identities. Older two-key settings
files work with empty order arrays. The old `umgpt-defaults` and
`apply-umgpt-defaults` commands remain aliases; new examples use
`model-settings` and `apply-model-settings`.

## How picker catalogs work

The CLI `/model` menu and VS Code model picker use a saved catalog. Without a
custom catalog, they can show only bundled OpenAI models even when another
model is active. `refresh-models NAME` fetches the live gateway list, filters
it to the identity's scope, and writes `model-catalog.json` in that home. It
sets the top-level [`model_catalog_json` configuration](https://learn.chatgpt.com/docs/config-file/config-reference).
The checked-in snapshot and defaults file are not runtime catalogs.

Automatic order is Claude → GPT → o-series → Gemini → other families
alphabetically, with numeric versions descending within each family. Equal
versions sort alphabetically; IDs without a version come last. This is
inferred from IDs, not release dates. Duplicate favorites appear once;
unavailable favorites stay saved and are skipped until available.

Codex treats the first picker entry as its recommended default, so the helper
pins the configured default before favorites. Printed `models` lists show
favorites first. Applying settings reorders existing helper-owned catalogs
offline; a live refresh discovers new models. Resumed sessions and explicit
session overrides can retain a different selection. Ordinary launches use the
saved catalog without a discovery request.

For recognized IDs, the helper uses metadata from the installed Codex CLI.
Other IDs receive generic coding instructions and conservative text-only
settings, without advertised reasoning levels or an assumed context-window
size. A picker entry does not establish Responses API, streaming, or tool-call
compatibility: run the [tool-call test](api-providers.md#validate-compatibility)
for each model you intend to use. Update Codex if it does not support
`codex debug models --bundled`.

A failed gateway request, invalid catalog, or missing configured default leaves
the previous catalog and configuration intact. A user-managed catalog at another
path blocks refresh; review and back up the configuration before removing its
`model_catalog_json` entry if you want the helper to manage it.

## Refresh and recovery

To discover newly added models, refresh each identity you use, then
[reload and verify](../MODELS.md#change-defaults-and-order):

```bash
./bin/codex-home refresh-models umgpt
./bin/codex-home refresh-models umgpt-low
```

| What you see | What to do |
|---|---|
| Edited file, old selection in VS Code | Run `apply-model-settings`, reload the window, and start a new chat. Check the exact personal file path with `model-settings`. |
| Picker shows bundled OpenAI models only | Run `refresh-models NAME`, then reload. `models NAME` only prints IDs. |
| Default is missing from the saved catalog | Run `refresh-models NAME`, then retry `apply-model-settings`. A default must exist in the catalog; if absent from the live list too, choose an available ID. |
| A preferred model does not appear | Check the live scoped list and spelling. Missing preferences remain saved for future refreshes. |
| Invalid settings or an out-of-scope model | Fix the reported file line or ID and apply again. Keep arrays on one line. Validation failures leave identity configurations and catalogs unchanged. |
| One identity updated, then applying the other failed | Fix the reported identity or catalog problem and rerun apply. Settings stay in the personal file; each completed update is printed. |
| A failed gateway refresh | The previous catalog and configuration remain intact. Check the endpoint/key and retry; see [troubleshooting](troubleshooting.md). |
| A custom catalog blocks applying | Review the identity's `model_catalog_json`. The helper reorders only its own catalog; see [catalog behavior](#how-picker-catalogs-work). |

[← Back to model settings and comparison](../MODELS.md)
