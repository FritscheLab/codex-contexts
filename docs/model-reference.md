# Model reference

[Model settings](../MODELS.md)

- **Comparison details:** [Prices and limits](#prices-and-limits) | [Benchmark notes](#benchmark-notes)
- **Picker help:** [Available models](#available-models) | [Other settings](#other-model-settings) | [Catalog behavior](#how-picker-catalogs-work) | [Refresh and recovery](#refresh-and-recovery)

## Prices and limits

Prices and benchmark scores were checked on **16 November 2026**. Prices use
U-M GPT Toolkit standard rates in USD per million tokens. Scores use the
Artificial Analysis **Intelligence Index v5.0.1**.
[Toolkit prices and model approvals](https://its.umich.edu/computing/ai/pricing#u-m-gpt-toolkit) | [Benchmark methodology](https://artificialanalysis.ai/methodology/intelligence-benchmarking)

| Model | Evaluated effort | Index | U-M input | U-M output | Tokens/s (1) | Toolkit ePHI approved (2) |
|---|---|---:|---:|---:|---:|---|
| [GPT-6 Luna](https://artificialanalysis.ai/models/creators/openai) | Medium | 18 | $0.10 | $0.50 | 95 | Yes |
| [GPT-6 Sol](https://artificialanalysis.ai/models/creators/openai) | Medium | n/a | $2.00 | $10.00 | n/a | Yes |
| [GPT-6 Astra](https://artificialanalysis.ai/models/creators/openai) | Medium | 52 | $10.00 | $50.00 | 44 | Yes |
| [GPT-6.1 Sol](https://artificialanalysis.ai/models/creators/openai) | Medium | 46 | $2.00 | $10.00 | 52 | Yes |
| [Claude Haiku 4.5](https://artificialanalysis.ai/models/creators/anthropic) | Reasoning | 7 | $1.00 | $5.00 | 116 | No |
| [Claude Haiku 5.5](https://artificialanalysis.ai/models/creators/anthropic) | Medium | 25 | $0.10 | $0.50 | 221 | No |
| [Claude Sonnet 5](https://artificialanalysis.ai/models/creators/anthropic) | Medium | n/a | $2.20 | $11.00 | 102 | No |
| [Claude Sonnet 5.5](https://artificialanalysis.ai/models/creators/anthropic) | Medium with evaluator default fallback | 31 | $2.00 | $10.00 | 128 | No |
| [Claude Opus 5.5](https://artificialanalysis.ai/models/creators/anthropic) | Medium with evaluator default fallback | 48 | $4.40 | $22.00 | 107 | No |
| [Claude Fable 5.1](https://artificialanalysis.ai/models/creators/anthropic) | Medium with evaluator default fallback | 43 | $11.00 | $55.00 | 87 | No |
| [Claude Fable 5.2](https://artificialanalysis.ai/models/creators/anthropic) | Medium with evaluator default fallback | 56 | $8.80 | $44.00 | 104 | No |
| [Gemini 3.8 Flash](https://artificialanalysis.ai/models/creators/google) | Medium | 30 | $0.75 | $3.75 | 118 | No |
| [Grok 4.6](https://artificialanalysis.ai/models/grok-4-6) | Xhigh | 31 | $1.25 | $6.00 | 71 | No |
| [DeepSeek V4 Flash 0731](https://artificialanalysis.ai/models/deepseek-v4-flash) | Max | n/a | $0.19 | $0.51 | 141 | No |
| [DeepSeek V4.1 Flash](https://artificialanalysis.ai/models/deepseek-v4-1-flash) | Max with gateway revision unverified | n/a | $0.30 | $1.20 | n/a | No |
| [DeepSeek V4 Pro](https://artificialanalysis.ai/models/deepseek-v4-pro) | Max with gateway revision unverified | n/a | $1.74 | $3.48 | n/a | No |
| [Kimi K3](https://artificialanalysis.ai/models/kimi-k3) | Max | n/a | $3.00 | $15.00 | 48 | No |
| [Kimi K2.5](https://artificialanalysis.ai/models/kimi-k2-5) | Reasoning | n/a | $0.60 | $3.00 | 43 | No |

(1) The evaluator measures output speed including time to first token. `n/a` marks
an unavailable comparable value. [Speed methodology](https://artificialanalysis.ai/methodology)

(2) Electronic protected health information (ePHI) status is for the Toolkit
route. U-M ITS listings were checked by model ID on **25 November 2026**. Check
whether your Codex workflow and API key meet the Sensitive Data Guide and your
unit's requirements before using ePHI.
[Toolkit model approvals](https://its.umich.edu/computing/ai/pricing#u-m-gpt-toolkit) | [Launch and verify an ePHI-restricted project](umgpt.md#check-data-permissions-first)

[Model data and sources (CSV)](data/model-benchmarks.csv)

### Pricing basis

Check actual charges and quotas in the Toolkit portal. Cache and context can
change the billed rates. Reasoning effort affects token use, and a Codex task
can make multiple requests. Compare task costs with measured token use and
charges at the settings you plan to use.
[Toolkit portal](https://toolkit.umgpt.umich.edu/) | [Reasoning and token usage](https://developers.openai.com/api/docs/guides/reasoning#controlling-costs)

### Context and cache conditions

- **Claude Haiku 5.5:** Anthropic's base input/output rates apply through 100K
  input tokens; above that, its rates are five times higher. Cache rates also
  change. Its provider limits are 1M context and 128K output.
  [Exact model specifications](https://platform.claude.com/docs/en/models/haiku-5-5/overview).
- **GPT-6.1 Sol:** OpenAI's provider schedule doubles input/cache prices and
  increases output prices by 50% when input exceeds 272K tokens, for the full
  request. Provider limits are 1,050,000 context and 128,000 output tokens.
  [Exact model specifications](https://developers.openai.com/api/docs/models/gpt-6.1-sol).
- **Grok and DeepSeek:** direct-provider rates and context/time tiers can differ
  from Toolkit estimates. Use the exact route's terms rather than transferring
  a direct rate to the U-M endpoint.
  [Grok model specifications](https://docs.x.ai/developers/models/grok-4.6),
  [DeepSeek pricing](https://api-docs.deepseek.com/quick_start/pricing/).

Provider limits do not verify U-M deployment limits or change the helper's
conservative runtime metadata. Instructions, tools, and history also consume
context. See [catalog behavior](#how-picker-catalogs-work).

## Benchmark notes

Compare scores at matching reasoning settings. The evaluator's fallback
configurations are marked in the table. Resolve gateway model aliases before
using a benchmark from another revision. The evaluator supplies no uncertainty
intervals, so small score gaps may be uninformative. Check compatibility with
your chosen model and key.
[Tool-call test](api-providers.md#validate-compatibility)

## Available models

Print the model IDs available to your key and allowed by the identity's scope.

```bash
codex-home models umgpt
codex-home models umgpt-low
```

Use `refresh-models NAME` to update the picker. [Catalog snapshot and classifications](umgpt-models-snapshot.md) | [Local filtering rules](umgpt.md#exact-local-filtering-rules)

## Other model settings

The [main guide](../MODELS.md#change-defaults-and-order) covers editing and applying
settings. These options address less common cases.

| Need | Action |
|---|---|
| Change one default quickly | `./bin/codex-home set-umgpt-default umgpt MODEL` (or `umgpt-low`); retains favorite order |
| Use a model for one CLI session | `./bin/codex-home run NAME -m MODEL`; use an exact ID within that identity's scope; saved choices stay unchanged |
| Reset order only | Set both order arrays to `[]`, then apply |
| Adopt repository defaults and order | `./bin/codex-home reset-umgpt-defaults`; **overwrites personal choices**, then reload |
| Use another settings file | Set `CODEX_UMGPT_MODELS_FILE` to its path |

Additional named identities retain their configured defaults. Favorites apply
by scope on their next `refresh-models NAME`. `apply-model-settings` updates
the standard `umgpt` and `umgpt-low` identities. Settings files with just the
two defaults use automatic order.

## How picker catalogs work

The CLI `/model` menu and VS Code model picker use a saved catalog. Without a
custom catalog, they can show only bundled OpenAI models even when another
model is active. `refresh-models NAME` fetches the live gateway list, filters
it to the identity's scope, and writes `model-catalog.json` in that home. It
sets the top-level [`model_catalog_json` configuration](https://learn.chatgpt.com/docs/config-file/config-reference).

Automatic order is Claude, GPT, o-series, Gemini, then other families
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
codex-home refresh-models umgpt
codex-home refresh-models umgpt-low
```

If the gateway retired the active model, use `codex-home models NAME` to find
an available ID, then run `codex-home refresh-models NAME --model MODEL`.
This updates the identity's active default and picker. For a standard identity,
run `codex-home set-umgpt-default NAME MODEL` afterward to save the choice in
your personal settings as well.

| What you see | What to do |
|---|---|
| Edited file, old selection in VS Code | Run `apply-model-settings`, reload the window, and start a new chat. Check the exact personal file path with `model-settings`. |
| Picker shows bundled OpenAI models only | Run `refresh-models NAME`, then reload. `models NAME` only prints IDs. |
| Saved default is missing from the picker | Run `refresh-models NAME --model MODEL` with that model if the gateway advertises it, then retry `apply-model-settings`. If it was retired, choose an advertised replacement and save that preference. |
| A preferred model does not appear | Check the live scoped list and spelling. Missing preferences remain saved for future refreshes. |
| Invalid settings or an out-of-scope model | Fix the reported file line or ID and apply again. Keep arrays on one line. Validation failures leave identity configurations and catalogs unchanged. |
| One identity updated, then applying the other failed | Fix the reported identity or catalog problem and rerun apply. Settings stay in the personal file; each completed update is printed. |
| A failed gateway refresh | The previous catalog and configuration remain intact. Check the endpoint/key and retry; see [troubleshooting](troubleshooting.md). |
| A custom catalog blocks applying | Review the identity's `model_catalog_json`. The helper reorders only its own catalog; see [catalog behavior](#how-picker-catalogs-work). |

[Back to model settings](../MODELS.md)
