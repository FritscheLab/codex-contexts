# U-M GPT API setup

[Connect](#connect) | [Data permissions](#check-data-permissions-first) | [Scope rules](#exact-local-filtering-rules) | [Models and pickers](../MODELS.md)

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

Assign an ePHI-restricted project to its intended Toolkit identity and review
and approve the folder's `.envrc` in direnv. Each time you start a session,
choose `codex-home run` or `codex-home vscode-project` from that folder, or use
Finder's **Open in Codex Project** action. If your shell has no direnv hook,
run `direnv exec . codex-home run` from the folder. Plain `codex` and ordinary
**Open With > VS Code** skip the helper's launch checks, even if they inherit
the intended `CODEX_HOME`. Keep ePHI out of the session until you confirm the
active Toolkit route and exact model.
[Session checks](commands.md#check-the-selected-identity)

For electronic protected health information (ePHI), check the **ePHI Approved**
column for your exact model in the U-M GPT Toolkit table. Confirm the Codex
workflow and API key against the Sensitive Data Guide and your unit's
requirements. Michigan Medicine routes ePHI applications requesting Toolkit
keys through Information Assurance review and restricts automated workflows.
Recheck when the model or use case changes. [Toolkit model approvals](https://its.umich.edu/computing/ai/pricing#u-m-gpt-toolkit) | [Sensitive Data Guide](https://safecomputing.umich.edu/dataguide/service/75) | [Michigan Medicine guidance](https://safecomputing.umich.edu/michigan-medicine/employee-resources/using-gpt-at-michigan-medicine)

You can also [deny sandboxed reads of the restricted folder](security.md#deny-sandboxed-reads-of-a-folder)
in your everyday Codex identities.

The [ITS FAQ](https://its.umich.edu/computing/ai/faq) describes moderately
sensitive-data use; it does not make every model interchangeable. Do not use
AI output as the basis for patient-care or clinical-support decisions.

## Connect

These commands assume `codex-home` is on `PATH`. [Installation](../INSTALLATION.md)
For native Codex settings, follow the [U-M Toolkit instructions](https://its.umich.edu/computing/ai/codex-gpt-toolkit) and launch from a [separate home](manual-setup.md).

1. Obtain a key from the [Toolkit portal](https://toolkit.umgpt.umich.edu/).
2. Discover the exact model IDs available to that key:

   ```bash
   codex-home probe-models https://api.toolkit.umgpt.umich.edu/v1
   ```

   The command sends the key to the Toolkit `/models` endpoint and uses it
   for this request. Compare the live IDs with
   [saved defaults](../MODELS.md).
3. Create the identity you need and store its key:

   ```bash
   codex-home create-umgpt
   codex-home set-key umgpt
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

The helper checks the identity and ancestor project configurations at launch,
including the directory named by `-C` or `--cd`. It rejects provider routing
changes and model overrides outside the configured scope. Scope checks use
model ID patterns and do not enforce the Toolkit's ePHI approval list. Check
approval for the exact selected model and workflow. Start a new chat after
switching identities and recheck the active model after changes within the
session. [Permissions and credentials](security.md)

## What "Azure OpenAI" means here

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
codex-home set-umgpt-scope umgpt openai-only
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
codex-home create-umgpt gpt-6-sol umgpt-study-a
codex-home set-key umgpt-study-a
```

For broader models, use `create-umgpt-low MODEL NAME`. Creation without a model
uses the saved default. Applying or resetting defaults updates only the
standard `umgpt`/`umgpt-low` identities; named identities keep their configured
models. See [model controls](../MODELS.md) and
[provider errors](api-providers.md#provider-errors) for the next change or fix.
