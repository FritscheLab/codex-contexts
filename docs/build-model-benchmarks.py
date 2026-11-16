#!/usr/bin/env python3
"""Render the dated model comparison from verified CSV data; never fetch prices.

Run from the repository root: python3 docs/build-model-benchmarks.py
Requires matplotlib. Produces PNG for Markdown and editable SVG for download.
"""

import argparse
import csv
from datetime import date
from decimal import Decimal
from math import ceil, floor, isfinite, log10
from pathlib import Path
import textwrap

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.ticker import FixedLocator, FuncFormatter, NullLocator


DOCS = Path(__file__).resolve().parent
INK = "#19293B"
MUTED = "#51647B"
TEAL = "#15758A"
GREEN = "#2C9654"


def read_data(path):
    with path.open(newline="", encoding="utf-8") as source:
        rows = list(csv.DictReader(source))
    if not rows:
        raise ValueError("No benchmark rows to plot")
    versions = {r["index_version"] for r in rows}
    if len(versions) != 1:
        raise ValueError("Do not mix Intelligence Index versions in one figure")
    current = "umgpt_input_usd_per_million" in rows[0]
    if versions != {"5.0.1" if current else "4.3.2"}:
        raise ValueError("Expected v5.0.1 for Toolkit prices or v4.3.2 for the historical provider snapshot")
    if len({r["checked_date"] for r in rows}) != 1:
        raise ValueError("Use one verification date per snapshot")
    seen = set()
    for row in rows:
        key = (row["model_id"], row["reasoning"])
        if key in seen:
            raise ValueError(f"Duplicate model/setting: {key}")
        seen.add(key)
        row["current"] = current
        row["score"] = float(row["score"]) if row["score"] else None
        if row["score"] is not None and not isfinite(row["score"]):
            raise ValueError(f"Benchmark score must be finite: {key}")
        statuses = ("evaluated", "unavailable", "alias-unverified") if current else ("evaluated", "estimated")
        if row["benchmark_status"] not in statuses:
            raise ValueError(f"Unknown benchmark status: {key}")
        verified = row["benchmark_status"] in ("evaluated", "estimated")
        if verified != (row["score"] is not None):
            raise ValueError(f"Only evaluated or estimated rows may contain a benchmark score: {key}")
        adjustment = Decimal(0 if current else row["price_adjustment_percent"])
        if not adjustment.is_finite() or adjustment < 0:
            raise ValueError(f"Adjustment must be finite and nonnegative: {key}")
        if adjustment and not row["adjustment_source"]:
            raise ValueError(f"Price adjustment needs a source: {key}")
        for direction in ("input", "output"):
            basis = "umgpt" if current else "direct"
            value = row[f"{basis}_{direction}_usd_per_million"]
            field = f"plot_{direction}_usd_per_million"
            row[field] = float(Decimal(value) * (1 + adjustment / 100)) if value else None
            if row[field] is not None and (not isfinite(row[field]) or row[field] <= 0):
                raise ValueError(f"Log price must be positive: {key}, {field}")
    return rows


def point_label(row):
    label = row["label"].replace("Claude ", "")
    if row["model_id"] == "claude-sonnet-5":
        label += " (high)" if "high" in row["reasoning"] else " (medium)"
    if row["current"] and row["model_id"] == "grok-4.6":
        label += " (xhigh)"
    if row["repository_default"]:
        label += "\nDefault for both" if row["repository_default"] == "umgpt;umgpt-low" else f"\n{row['repository_default']} default"
    return label


def render(rows, output_dir):
    current = rows[0]["current"]
    scored = [row for row in rows if row["score"] is not None]
    if not scored:
        raise ValueError("No verified benchmark scores to plot")
    plt.rcParams.update({
        "font.family": "DejaVu Sans", "font.size": 12,
        "text.color": INK, "axes.labelcolor": MUTED,
        "xtick.color": MUTED, "ytick.color": MUTED,
        "svg.fonttype": "none", "svg.hashsalt": "codex-model-comparison",
        "savefig.facecolor": "white",
    })
    fig, axes = plt.subplots(1, 2, figsize=(16, 11), sharey=True)
    fig.subplots_adjust(left=0.085, right=0.97, top=0.73,
                        bottom=0.32 if current else 0.265, wspace=0.12)
    checked = date.fromisoformat(rows[0]["checked_date"]).strftime("%d %b %Y")
    title = "Model capability vs U-M Toolkit token price" if current else "Model capability vs provider token price"
    fig.text(0.085, 0.935, title,
             fontsize=24, weight="bold")
    fig.text(0.085, 0.894,
             f"Artificial Analysis Intelligence Index v{rows[0]['index_version']}"
             f"  ·  USD per 1 million tokens  ·  {checked}",
             fontsize=12.5, color=MUTED)
    fig.text(0.085, 0.852,
             "Higher and further left = higher benchmark score at a lower token price",
             fontsize=12.5, color=MUTED)
    legend = [
        Line2D([], [], marker="o", color="none", markerfacecolor=TEAL,
               markeredgecolor="white", markersize=11, label="Evaluated score"),
        Line2D([], [], marker="D", color="none", markerfacecolor=GREEN,
               markeredgecolor="#226D40", markersize=10,
               label="Repository default"),
    ]
    if not current:
        legend.insert(1, Line2D([], [], marker="o", color="none", markerfacecolor="white",
                               markeredgecolor=TEAL, markeredgewidth=1.8, markersize=10,
                               label="Estimated score"))
    fig.legend(handles=legend, loc="upper left", bbox_to_anchor=(0.075, 0.827),
               ncol=len(legend), frameon=False)

    omitted_scores = {row["label"] for row in rows if row["score"] is None}
    omitted_prices = set()
    counts = []
    for ax, direction in zip(axes, ("input", "output")):
        field = f"plot_{direction}_usd_per_million"
        included = [r for r in scored if r[field] is not None]
        counts.append(len(included))
        omitted_prices.update(r["label"] for r in scored if r[field] is None)
        ax.set_title(f"{direction.capitalize()} price", loc="left", pad=18,
                     fontsize=18, weight="bold", color=INK)
        ax.set_xscale("log")
        # Input and output share a log scale; each has labeled price units.
        ax.set_xlim((0.075, 16) if direction == "input" else (0.20, 80))
        ticks = [0.1, 0.2, 0.5, 1, 2, 5, 10] if direction == "input" else [0.25, 0.5, 1, 2, 5, 10, 20, 50]
        if current:
            prices = [row[field] for row in included]
            if not prices:
                raise ValueError(f"No verified benchmark rows have a {direction} price")
            ax.set_xlim(min(prices) / 1.35, max(prices) * 1.5)
            ticks = [multiple * 10 ** exponent
                     for exponent in range(floor(log10(min(prices))), ceil(log10(max(prices))) + 1)
                     for multiple in (1, 2, 5)
                     if ax.get_xlim()[0] <= multiple * 10 ** exponent <= ax.get_xlim()[1]]
        ax.xaxis.set_major_locator(FixedLocator(ticks))
        ax.xaxis.set_major_formatter(FuncFormatter(lambda x, _: f"${x:g}"))
        ax.xaxis.set_minor_locator(NullLocator())
        ax.set_ylim(3, 59)
        ax.set_yticks(range(5, 60, 5))
        if current:
            lower = max(0, floor(min(row["score"] for row in scored) / 5) * 5 - 5)
            upper = ceil(max(row["score"] for row in scored) / 5) * 5 + 5
            ax.set_ylim(lower, upper)
            ax.set_yticks(range(lower, upper + 1, 10))
        ax.grid(color="#E7EDF3", linewidth=1)
        ax.set_axisbelow(True)
        ax.tick_params(length=0, pad=10)
        for side in ("top", "right"):
            ax.spines[side].set_visible(False)
        for side in ("left", "bottom"):
            ax.spines[side].set_color("#7D8EA3")
        ax.set_xlabel(f"USD per 1M {direction} tokens · log scale", labelpad=15)
        for row in included:
            is_default = bool(row["repository_default"])
            is_estimated = row["benchmark_status"] == "estimated"
            point = ax.scatter(row[field], row["score"], s=115 if is_default else 95,
                               marker="D" if is_default else "o",
                               facecolors="white" if is_estimated else GREEN if is_default else TEAL,
                               edgecolors=TEAL if is_estimated else "#226D40" if is_default else "white",
                               linewidths=1.8 if is_estimated else 1.4, zorder=3)
            # Rightmost labels extend left; nearby equal scores separate vertically.
            dx, dy, align = 9, 8, "left"
            if row["model_id"] in ("gpt-6-astra", "claude-opus-5-5", "claude-fable-5-1"):
                dx, align = -9, "right"
            if row["model_id"] == "gpt-6-astra":
                dy = 32
            if row["model_id"] == "claude-fable-5-1":
                dy = -27
            if row["model_id"] == "gpt-6-sol":
                dy = -20
            if row["model_id"] == "claude-opus-5-5":
                dx, dy = -12, 12
            if row["model_id"] == "kimi-k3":
                dx, dy = 10, -8
            if row["model_id"] == "Llama-4-Scout-17B-16E-Instruct":
                dy = -12
            if row["model_id"] == "claude-sonnet-5" and "medium" in row["reasoning"]:
                dy = -19
            if current:
                dx, dy, align = {
                    "gpt-6-luna": (10, -2, "left"),
                    "gpt-6-astra": (-9, -8, "right"),
                    "gpt-6.1-sol": (-9, -20, "right"),
                    "claude-haiku-4-5": (9, 7, "left"),
                    "claude-haiku-5-5": (10, 0, "left"),
                    "claude-sonnet-5-5": (9, -2, "left"),
                    "claude-opus-5-5": (9, 0, "left"),
                    "claude-fable-5-1": (-9, -7, "right"),
                    "claude-fable-5-2": (-9, 14, "right"),
                    "gemini-3.8-flash": (9, -20, "left"),
                    "grok-4.6": (-9, 14, "right"),
                }.get(row["model_id"], (9, 8, "left"))
            ax.annotate(point_label(row), (row[field], row["score"]),
                        xytext=(dx, dy), textcoords="offset points", ha=align,
                        fontsize=11, weight="semibold", linespacing=1.35,
                        arrowprops={"arrowstyle": "-", "color": MUTED, "lw": 0.7}
                        if (current and abs(dy) >= 14) or row["model_id"] in ("gpt-6-astra", "claude-fable-5-1") else None)
            # Check the actual plotted geometry against the untransformed source.
            assert tuple(point.get_offsets()[0]) == (row[field], row["score"])
            assert ax.get_xlim()[0] <= row[field] <= ax.get_xlim()[1]
            assert ax.get_ylim()[0] <= row["score"] <= ax.get_ylim()[1]
        assert len(ax.collections) == len(included)
    axes[0].set_ylabel("Intelligence Index score · higher is better", labelpad=14)
    notes = [
        "Provider rates; only Opus 5.5 input/output include the verified 10% U-M adjustment. No blanket fee. Cache charges excluded.",
        "GPT-6 prices: ≤272K input; Gemini prices: through 31 Dec 2026. Token price is not cost per completed task.",
        "GPT-6/Gemini: medium. Sonnet: labeled effort. Haiku/K2.5: reasoning. DeepSeek/K3: max. Llama: non-reasoning.",
        "Opus/Fable: medium, evaluator's default fallback. No uncertainty intervals supplied; small score gaps may not be meaningful.",
        "Scores are external model benchmarks, not U-M deployment tests. Defaults reflect the repository template at the snapshot date.",
    ]
    if current:
        notes = [
            "U-M Toolkit posted price estimates; USD per 1M tokens. Cache charges excluded. Check actual route billing.",
            "Scores: medium, except Haiku 4.5 (reasoning) and Grok 4.6 (xhigh). Sonnet 5.5, Opus 5.5, and Fable use evaluator default fallback.",
            "Provider long-context tiers: Haiku 5.5 above 100K input; GPT-6.1 Sol above 272K input. U-M tier billing unverified; see guide.",
            "External Artificial Analysis scores, not Toolkit deployment tests. No uncertainty intervals supplied; small gaps may not be meaningful.",
            "Token price does not measure cost per completed task. The default marker identifies the repository setting, not a benchmark winner.",
        ]
    if omitted_scores:
        notes.append(f"{len(omitted_scores)} models omitted (benchmark unavailable or alias unverified): {', '.join(sorted(omitted_scores))}.")
    if omitted_prices:
        notes.append(f"Missing prices (not plotted): {', '.join(sorted(omitted_prices))}.")
    divider_y = 0.25 if current else 0.195
    fig.add_artist(Line2D([0.085, 0.97], [divider_y, divider_y], transform=fig.transFigure,
                          color="#D7E1EA", linewidth=1))
    lines = [line for note in notes for line in (textwrap.wrap(note, width=145) if current else [note])]
    first_note_y = 0.228 if current else 0.173
    note_spacing = 0.024 if current else 0.025
    for i, line in enumerate(lines):
        fig.text(0.085, first_note_y - i * note_spacing, line, fontsize=10, color=MUTED)
    data_name = "model-benchmarks-current.csv" if current else "model-benchmarks.csv"
    fig.text(0.085, 0.023, f"Sources and exact values: docs/data/{data_name}  ·  Guide: MODELS.md",
             fontsize=9.5, color=MUTED)
    output_dir.mkdir(parents=True, exist_ok=True)
    stem = output_dir / ("model-cost-performance-umgpt" if current else "model-cost-performance-direct")
    fig.savefig(stem.with_suffix(".png"), dpi=150)
    fig.savefig(stem.with_suffix(".svg"), metadata={"Date": rows[0]["checked_date"]})
    plt.close(fig)
    print(f"Rendered {stem.name}: {counts[0]} input / {counts[1]} output points; "
          f"omitted scores ({len(omitted_scores)}): {', '.join(sorted(omitted_scores)) or 'none'}; "
          f"omitted prices: {', '.join(sorted(omitted_prices)) or 'none'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, default=DOCS / "data/model-benchmarks-current.csv")
    parser.add_argument("--output-dir", type=Path, default=DOCS / "images")
    args = parser.parse_args()
    rows = read_data(args.data)
    render(rows, args.output_dir)


if __name__ == "__main__":
    main()
