#!/usr/bin/env python3
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
RAW_CSV = ROOT / "results" / "raw" / "results_raw.csv"
SUMMARY_CSV = ROOT / "results" / "summary" / "results_summary.csv"
PLOTS_DIR = ROOT / "results" / "plots"

PLOTS_DIR.mkdir(parents=True, exist_ok=True)
SUMMARY_CSV.parent.mkdir(parents=True, exist_ok=True)

if not RAW_CSV.exists():
    raise SystemExit(f"Raw CSV not found: {RAW_CSV}")

df = pd.read_csv(RAW_CSV)
if df.empty:
    raise SystemExit("Raw CSV is empty; nothing to analyze.")

num_cols = [
    "delay_ms",
    "jitter_ms",
    "loss_percent",
    "avg_latency_ms",
    "p95_latency_ms",
    "p99_latency_ms",
    "throughput_rps",
    "error_rate",
    "concurrency",
]
for c in num_cols:
    df[c] = pd.to_numeric(df[c], errors="coerce")

summary = (
    df.groupby(["protocol", "scenario", "workload", "concurrency", "loss_percent"], as_index=False)
    .agg(
        avg_latency_ms=("avg_latency_ms", "mean"),
        p95_latency_ms=("p95_latency_ms", "mean"),
        p99_latency_ms=("p99_latency_ms", "mean"),
        throughput_rps=("throughput_rps", "mean"),
        error_rate=("error_rate", "mean"),
    )
    .sort_values(["workload", "concurrency", "loss_percent", "protocol"])
)
summary.to_csv(SUMMARY_CSV, index=False)

plot_workload = "small-static" if (summary["workload"] == "small-static").any() else summary["workload"].iloc[0]
plot_conc = int(summary["concurrency"].min())
plot_df = summary[(summary["workload"] == plot_workload) & (summary["concurrency"] == plot_conc)].copy()

if plot_df.empty:
    raise SystemExit("No rows available for plotting.")

metrics = [
    ("p95_latency_ms", "P95 latency, ms", "p95_latency_by_loss.png"),
    ("p99_latency_ms", "P99 latency, ms", "p99_latency_by_loss.png"),
    ("throughput_rps", "Throughput, req/s", "throughput_by_loss.png"),
    ("error_rate", "Error rate", "error_rate_by_loss.png"),
]

for metric, ylabel, fname in metrics:
    plt.figure(figsize=(8, 5))
    for proto in ["h2", "h3"]:
        part = plot_df[plot_df["protocol"] == proto].sort_values("loss_percent")
        if part.empty:
            continue
        plt.plot(part["loss_percent"], part[metric], marker="o", label=proto.upper())
    plt.title(f"{ylabel} vs loss ({plot_workload}, c={plot_conc})")
    plt.xlabel("Packet loss, %")
    plt.ylabel(ylabel)
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.savefig(PLOTS_DIR / fname, dpi=150)
    plt.close()

print(f"Summary saved to: {SUMMARY_CSV}")
print(f"Plots saved to: {PLOTS_DIR}")
