# Model reference

[← Compare models and change settings](../MODELS.md)

- **Comparison details:** [Prices and limits](#prices-and-limits) · [Benchmark notes](#benchmark-notes)
- **Picker help:** [Available models](#available-models) · [Other settings](#other-model-settings) · [Catalog behavior](#how-picker-catalogs-work) · [Refresh and recovery](#refresh-and-recovery)

## Prices and limits

Checked **2026-11-16**. The [current comparison](../MODELS.md#compare-models)
uses the standard input/output estimates posted by
[U-M ITS for the GPT Toolkit](https://its.umich.edu/computing/ai/pricing), in USD
per million tokens. These replace the September comparison's mixture of direct
provider prices and an Opus-specific adjustment. Each current CSV row records
its price source and verification date; no provider markup is inferred.

### Pricing basis

Use the Toolkit rates for planning Toolkit work. A direct provider's price can
differ from U-M's posted rate. ITS says estimates depend on context and cache
and are subject to change. Confirm actual charges and quotas in the
[Toolkit portal](https://toolkit.umgpt.umich.edu/).

The displayed columns cover standard input and output tokens. They do not
quote cache writes/reads, batch discounts, image generation, or a complete
cost per task. A Codex task can make several requests and generate reasoning
tokens. The source does not publish a separate U-M cache or long-context
schedule, so provider conditions below are context rather than a U-M quote.

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

The current comparison uses **Artificial Analysis Intelligence Index v5.0.1**,
which incorporates nine evaluations. Higher scores indicate higher aggregate
benchmark performance; the score is not percentage accuracy or a guarantee
of success on a particular task.
[Evaluator methodology](https://artificialanalysis.ai/methodology/intelligence-benchmarking).

Every row specifies the evaluated effort. Most current scores use medium;
Grok 4.6 uses xhigh. Some Claude results include the evaluator's default
fallback configuration. These are evaluator settings, not settings the helper
applies. Model-specific sources and qualifications are retained in the CSV.

Output speed comes from the evaluator's matching effort/model entry and uses
its current full-request measure, including time to first token. It is an
external endpoint measurement, not U-M throughput or total Codex task duration.
[Performance methodology](https://artificialanalysis.ai/methodology).

A dash means no verified comparable score or speed. In particular, do not
transfer a DeepSeek score from a dated variant to an unsuffixed gateway alias
without resolving the mapping. Rows with no usable score remain in the price
table and CSV but are excluded from the chart. The chart supplies no uncertainty
intervals; small score gaps may not be meaningful.

### Historical comparison

The [24 September 2026 archive](model-comparison-2026-09-24.md) preserves the
previous provider-price comparison and **v4.3.2** scores, including Llama rows
that are absent from the latest gateway response. Its CSV and figure remain
unchanged. Scores across the two index versions are not directly comparable.

### Update the comparison

[Current source data](data/model-benchmarks-current.csv) records exact IDs,
efforts, benchmark status, explicit Toolkit prices, dates, and source links.
Blank values stay blank; the renderer does not fetch or impute data.

After independently verifying and updating those records, regenerate the
PNG and editable SVG from the repository root with Matplotlib installed:

```bash
python3 docs/build-model-benchmarks.py
```

For the historical chart, select its original data explicitly:

```bash
python3 docs/build-model-benchmarks.py --data docs/data/model-benchmarks.csv
```

## Available models

The **2026-11-16** gateway snapshot contains **48 IDs**: **41 text models**
pass the general-text filter, and **18 GPT text models** also pass `umgpt`.
The text models comprise 12 Claude, 18 GPT, 5 Gemini, 3 DeepSeek, 2 Kimi, and
1 Grok. Seven image/embedding IDs are filtered out of both text scopes.
The current comparison covers 18 text IDs; omission does not imply
unavailability or poor performance.

Compared with the September snapshot, eight IDs were added. Both Llama IDs,
`o1`, and `o3` are absent from the latest response; this observation does not
establish permanent removal or remove o-series support from the helper.

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
