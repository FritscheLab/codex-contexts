# Model settings

[Change defaults and order](#change-defaults-and-order) | [Compare models](#compare-models) | [Picker and catalog reference](docs/model-reference.md)

Use these settings to choose the starting model and picker order for the
standard `umgpt` and `umgpt-low` identities. [U-M GPT setup](docs/umgpt.md)

## Change defaults and order

Create the identity you want to update and put `codex-home` on `PATH`.
[Installation](INSTALLATION.md)

**1. Find your settings file.**

```bash
codex-home model-settings
```

Open the path printed after **Edit your settings:**, normally
`~/.codex-homes/umgpt-models.toml`.

**2. Choose your defaults and favorites.**

```toml
umgpt = "gpt-6-luna"
umgpt_low = "gpt-6-luna"

umgpt_order = ["gpt-6.1-sol", "gpt-6-sol", "gpt-6-astra"]
umgpt_low_order = ["claude-sonnet-5", "gemini-3.8-flash", "claude-haiku-4-5"]
```

The first two lines select defaults; the arrays put your other favorites in
order. Keep each array on one line. Use `[]` for automatic ordering.
Find exact IDs in the [available model list](docs/model-reference.md#available-models).

The picker shows the default first, then favorites, then remaining models
by family and version.

**3. Apply, reload, and check.**

```bash
codex-home apply-model-settings
```

Restart the CLI, or run **Developer: Reload Window** in VS Code and start a
**new Codex chat**. Check your choices in the model picker. Run
`model-settings` again to compare saved and active defaults.

[Changes not showing?](docs/model-reference.md#refresh-and-recovery) | [Reset or use a model for one session](docs/model-reference.md#other-model-settings)

## Compare models

Run `codex-home models NAME` to see the model IDs available to your key.
[Toolkit prices, benchmarks, and ePHI status](docs/model-reference.md#prices-and-limits) | [Full catalog](docs/umgpt-models-snapshot.md) | [Compatibility check](docs/api-providers.md#validate-compatibility)
