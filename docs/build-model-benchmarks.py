#!/usr/bin/env python3
"""Render the dated model comparison from verified CSV data; never fetch prices.

Run from the repository root: python3 docs/build-model-benchmarks.py
Requires matplotlib. Produces PNG for Markdown and editable SVG for download.
"""

import argparse
import csv
from datetime import date
from decimal import Decimal
from math import isfinite
from pathlib import Path

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
    if {r["index_version"] for r in rows} != {"4.3.2"}:
        raise ValueError("This figure compares Intelligence Index v4.3.2 only")
    if len({r["checked_date"] for r in rows}) != 1:
        raise ValueError("Use one verification date per snapshot")
    seen = set()
    for row in rows:
        key = (row["model_id"], row["reasoning"])
        if key in seen:
            raise ValueError(f"Duplicate model/setting: {key}")
        seen.add(key)
        row["score"] = float(row["score"])
        if not isfinite(row["score"]):
            raise ValueError(f"Benchmark score must be finite: {key}")
        if row["benchmark_status"] not in ("evaluated", "estimated"):
            raise ValueError(f"Unknown benchmark status: {key}")
        adjustment = Decimal(row["price_adjustment_percent"])
        if not adjustment.is_finite() or adjustment < 0:
            raise ValueError(f"Adjustment must be finite and nonnegative: {key}")
        if adjustment and not row["adjustment_source"]:
            raise ValueError(f"Price adjustment needs a source: {key}")
        for direction in ("input", "output"):
            value = row[f"direct_{direction}_usd_per_million"]
            field = f"plot_{direction}_usd_per_million"
            row[field] = float(Decimal(value) * (1 + adjustment / 100)) if value else None
            if row[field] is not None and (not isfinite(row[field]) or row[field] <= 0):
                raise ValueError(f"Log price must be positive: {key}, {field}")
    return rows


def point_label(row):
    label = row["label"].replace("Claude ", "")
    if row["model_id"] == "claude-sonnet-5":
        label += " (high)" if "high" in row["reasoning"] else " (medium)"
    if row["repository_default"]:
        label += "\nDefault for both" if row["repository_default"] == "umgpt;umgpt-low" else f"\n{row['repository_default']} default"
    return label


def render(rows, output_dir):
    plt.rcParams.update({
        "font.family": "DejaVu Sans", "font.size": 12,
        "text.color": INK, "axes.labelcolor": MUTED,
        "xtick.color": MUTED, "ytick.color": MUTED,
        "svg.fonttype": "none", "svg.hashsalt": "codex-model-comparison",
        "savefig.facecolor": "white",
    })
    fig, axes = plt.subplots(1, 2, figsize=(16, 11), sharey=True)
    fig.subplots_adjust(left=0.085, right=0.97, top=0.73, bottom=0.265, wspace=0.12)
    checked = date.fromisoformat(rows[0]["checked_date"]).strftime("%d %b %Y")
    fig.text(0.085, 0.935, "Model capability vs provider token price",
             fontsize=24, weight="bold")
    fig.text(0.085, 0.894,
             f"Artificial Analysis Intelligence Index v{rows[0]['index_version']}"
             f"  ·  USD per 1 million tokens  ·  {checked}",
             fontsize=12.5, color=MUTED)
    fig.text(0.085, 0.852,
             "Higher and further left = higher benchmark score at a lower token price",
             fontsize=12.5, color=MUTED)
    fig.legend(handles=[
        Line2D([], [], marker="o", color="none", markerfacecolor=TEAL,
               markeredgecolor="white", markersize=11, label="Evaluated score"),
        Line2D([], [], marker="o", color="none", markerfacecolor="white",
               markeredgecolor=TEAL, markeredgewidth=1.8, markersize=10,
               label="Estimated score"),
        Line2D([], [], marker="D", color="none", markerfacecolor=GREEN,
               markeredgecolor="#226D40", markersize=10,
               label="Repository default"),
    ], loc="upper left", bbox_to_anchor=(0.075, 0.827), ncol=3, frameon=False)

    omitted = set()
    counts = []
    for ax, direction in zip(axes, ("input", "output")):
        field = f"plot_{direction}_usd_per_million"
        included = [r for r in rows if r[field] is not None]
        counts.append(len(included))
        omitted.update(r["label"] for r in rows if r[field] is None)
        ax.set_title(f"{direction.capitalize()} price", loc="left", pad=18,
                     fontsize=18, weight="bold", color=INK)
        ax.set_xscale("log")
        # Input and output share a log scale; each has labeled price units.
        ax.set_xlim((0.075, 16) if direction == "input" else (0.20, 80))
        ticks = [0.1, 0.2, 0.5, 1, 2, 5, 10] if direction == "input" else [0.25, 0.5, 1, 2, 5, 10, 20, 50]
        ax.xaxis.set_major_locator(FixedLocator(ticks))
        ax.xaxis.set_major_formatter(FuncFormatter(lambda x, _: f"${x:g}"))
        ax.xaxis.set_minor_locator(NullLocator())
        ax.set_ylim(3, 59)
        ax.set_yticks(range(5, 60, 5))
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
            ax.annotate(point_label(row), (row[field], row["score"]),
                        xytext=(dx, dy), textcoords="offset points", ha=align,
                        fontsize=11, weight="semibold", linespacing=1.35,
                        arrowprops={"arrowstyle": "-", "color": MUTED, "lw": 0.7}
                        if row["model_id"] in ("gpt-6-astra", "claude-fable-5-1") else None)
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
    if omitted:
        notes.append(f"Missing provider prices (not plotted): {', '.join(sorted(omitted))}.")
    fig.add_artist(Line2D([0.085, 0.97], [0.195, 0.195], transform=fig.transFigure,
                          color="#D7E1EA", linewidth=1))
    for i, note in enumerate(notes):
        y = 0.173 - i * 0.025
        fig.text(0.085, y, note, fontsize=10, color=MUTED)
    fig.text(0.085, 0.023, "Sources and exact values: docs/data/model-benchmarks.csv  ·  Guide: MODELS.md",
             fontsize=9.5, color=MUTED)
    output_dir.mkdir(parents=True, exist_ok=True)
    stem = output_dir / "model-cost-performance-direct"
    fig.savefig(stem.with_suffix(".png"), dpi=150)
    fig.savefig(stem.with_suffix(".svg"), metadata={"Date": rows[0]["checked_date"]})
    plt.close(fig)
    print(f"Rendered {stem.name}: {counts[0]} input / {counts[1]} output points; "
          f"omitted prices: {', '.join(sorted(omitted)) or 'none'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, default=DOCS / "data/model-benchmarks.csv")
    parser.add_argument("--output-dir", type=Path, default=DOCS / "images")
    args = parser.parse_args()
    rows = read_data(args.data)
    render(rows, args.output_dir)


if __name__ == "__main__":
    main()
