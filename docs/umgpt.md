# U-M GPT API setup

[Connect](#connect) · [Data permissions](#check-data-permissions-first) · [Scope rules](#exact-local-filtering-rules) · [Models and pickers](../MODELS.md)

Use a U-M GPT Toolkit API key for the gateway at
`https://api.toolkit.umgpt.umich.edu/v1`. This key is separate from a
ChatGPT login.

| Identity | Model scope |
|---|---|
| `umgpt` | GPT and o-series text IDs through U-M's Azure OpenAI-backed gateway |
| `umgpt-low` | Other general text models too; displays **LOW-SENSITIVITY DATA ONLY** |

Create only the scopes you need. These are local guardrails, not U-M data
classifications or institutional approval.

## Check data permissions first

Check the [ITS Sensitive Data Guide service entry](https://safecomputing.umich.edu/dataguide/service/75)
(U-M sign-in may be required), the
[model-specific restrictions](https://its.umich.edu/computing/ai/gpt-in-depth#models),
and your unit's requirements. For PHI, approval must cover both the selected
model and this Codex CLI/API workflow; permission for the service alone is
insufficient. Recheck when the model or use case changes.

The [ITS FAQ](https://its.umich.edu/computing/ai/faq) describes moderately
sensitive-data use; it does not make every model interchangeable. Do not use
AI output as the basis for patient-care or clinical-support decisions.

## Connect

1. Obtain a key from the [Toolkit portal](https://toolkit.umgpt.umich.edu/).
2. Discover the exact model IDs available to that key:

   ```bash
   ./bin/codex-home probe-models https://api.toolkit.umgpt.umich.edu/v1
   ```

   The hidden prompt does not store the key. Compare the live IDs with
   [model recommendations and saved defaults](../MODELS.md).
3. Create the identity you need and store its key:

   ```bash
   ./bin/codex-home create-umgpt
   ./bin/codex-home set-key umgpt
   ```

   For the broader scope, use `create-umgpt-low` and `set-key umgpt-low`.
   Creation without a model uses your saved default; inspect it with
   `model-settings` before creating the identity. To choose an initial model
   explicitly, pass its exact ID, for example
   `create-umgpt gpt-6-sol` or `create-umgpt-low claude-opus-5-5`.
   These are examples; confirm availability through discovery.
   For standard identity names, an explicit initial model also updates the
   saved default.
4. Run the [API compatibility and tool-call test](api-providers.md#validate-compatibility),
   replacing `research-api` with your U-M identity. Use non-sensitive content;
   repeat for every model you will use.

Keep keys out of commands, project files, chat, and logs. See
[credential storage and environment forwarding](security.md#secret-exposure-boundaries)
for the hidden-prompt and externally supplied-key options.

After testing, [verify the selected identity](commands.md#check-the-selected-identity)
and [configure its project](projects-vscode.md#generate-project-files).
For defaults, picker population/order, and reload steps, use
[Model settings and comparison](../MODELS.md) and
[picker recovery](model-reference.md#refresh-and-recovery).

### Costs and spending controls

[U-M GPT web chat is offered at no cost](https://its.umich.edu/computing/ai/pricing);
Toolkit API calls are billed by usage and are not covered by
[ChatGPT/Codex plan credits](https://learn.chatgpt.com/docs/pricing).
Check the [current ITS prices](https://its.umich.edu/computing/ai/pricing) and
the portal's quotas and **Total Spend**: one Codex task can make multiple
requests. [ITS says Toolkit keys require annual renewal](https://its.umich.edu/computing/ai/gpt-toolkit-in-depth).

## Exact local filtering rules

| Scope | Literal ID rule |
|---|---|
| `umgpt` | Case-sensitive `gpt-*` or `o[0-9]*` |
| `umgpt-low` | Any general text-model ID |
| Both | Reject IDs containing `image` or `embedding`, case-insensitively |

Thus `umgpt-low` includes the normal scope. Claude or Gemini IDs match only
the broader scope. These rules inspect names, not provider metadata; they
cannot establish a model's ownership, capabilities, or approval. The normal
identity is also pinned to the exact U-M gateway above.

## Guardrail boundaries

Before CLI or VS Code launches, the helper checks the identity and applicable
ancestor project configurations. U-M launches reject provider routing changes
and incompatible model overrides, including quoted or dotted TOML keys.
CLI checks use the requested `-C`/`--cd` directory.

The checks reduce accidental misuse. Direct `codex` launches, manual
configuration changes, runtime changes, or an existing session can bypass
them. Start a new session after switching identities and follow the
[verification steps](commands.md#check-the-selected-identity).
These safeguards do not isolate other processes running as your OS user;
see [permissions and credentials](security.md).

## What “Azure OpenAI” means here

[ITS describes U-M GPT](https://its.umich.edu/computing/ai) as offering hosted
Azure OpenAI models alongside U-M-hosted open-source models. Its
[FAQ](https://its.umich.edu/computing/ai/faq) and
[privacy notice](https://safecomputing.umich.edu/viziblue/ai-data) describe the
Azure environment and contractual controls. The official
[Codex Toolkit guide](https://its.umich.edu/computing/ai/codex-gpt-toolkit)
confirms that model requests use the Toolkit gateway without a separate
OpenAI API account.

A `gpt-*` ID reached with a direct OpenAI API key or ChatGPT account does not
inherit Toolkit protections. U-M's
[direct OpenAI product guidance](https://teamdynamix.umich.edu/TDClient/30/Portal/KB/Article/12163/Can-t-Connect-My-OpenAI-Account-Product-to-My-U-M-Google-or-Microsoft-365-Account)
states that those products lack a U-M DPA or BAA with OpenAI.

## Upgrade an older identity

Classify an older U-M identity before launching it:

```bash
./bin/codex-home set-umgpt-scope umgpt openai-only
```

Use `low-sensitivity` instead for an identity intentionally using broader
text models. An unclassified legacy identity is blocked. `openai-only`
means the U-M Azure OpenAI-backed gateway, rather than a direct OpenAI endpoint.

## Provider display names

New identities show `U-M GPT Toolkit (umgpt)` or
`U-M GPT Toolkit (umgpt-low; LOW-SENSITIVITY DATA ONLY)`, substituting custom
identity names when used.

For an existing identity, edit only `name` in its provider table in
`$CODEX_HOME/config.toml`. Keep `model_provider`, the provider-table ID,
and routing settings unchanged. The
[Codex name field](https://learn.chatgpt.com/docs/config-file/config-reference)
controls display; clients may still show the provider ID. Restart Codex
after editing. Repository updates do not rewrite existing identity files.

## Multiple U-M keys

Supply a custom identity name after the model ID:

```bash
./bin/codex-home create-umgpt gpt-6-sol umgpt-study-a
./bin/codex-home set-key umgpt-study-a
```

For broader models, use `create-umgpt-low MODEL NAME`. Creation without a model
uses the saved default. Applying or resetting defaults updates only the
standard `umgpt`/`umgpt-low` identities; named identities keep their configured
models. See [model controls](../MODELS.md) and
[provider errors](api-providers.md#provider-errors) for the next change or fix.
