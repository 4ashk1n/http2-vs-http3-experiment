# HTTP/2 vs HTTP/3 Experiment Stand

Experimental stand for reproducible comparison of HTTP/2 and HTTP/3 performance under network degradation (delay, jitter, packet loss).

## Requirements

- Ubuntu 22.04/24.04
- Docker + Docker Compose plugin
- sudo/root permissions
- UDP 443 availability (for HTTP/3)
- TCP 443 availability (for HTTP/2)
- Ability to run container with `NET_ADMIN` capability

## Run

```bash
docker compose up -d --build

./scripts/generate_data.sh

./scripts/check_protocols.sh

./scripts/run_quick_test.sh

./scripts/run_experiment.sh

python3 scripts/analyze.py
```

Equivalent Make targets:

```bash
make build
make up
make generate-data
make check
make quick
make experiment
make analyze
```

## Project Structure

```text
http2-http3-experiment/
├── README.md
├── docker-compose.yml
├── Caddyfile
├── Makefile
├── .gitignore
├── data/
│   ├── small/
│   ├── medium/
│   └── large/
├── scripts/
│   ├── generate_data.sh
│   ├── check_protocols.sh
│   ├── apply_netem.sh
│   ├── clear_netem.sh
│   ├── run_quick_test.sh
│   ├── run_experiment.sh
│   └── analyze.py
├── results/
│   ├── raw/
│   ├── summary/
│   └── plots/
└── docs/
    └── experiment_description.md
```

## Network Scenarios

- S1: delay 20ms, jitter 0ms, loss 0%
- S2: delay 50ms, jitter 5ms, loss 0.5%
- S3: delay 100ms, jitter 10ms, loss 1%
- S4: delay 150ms, jitter 20ms, loss 2%
- S5: delay 200ms, jitter 30ms, loss 5%

## Workloads

- `small-static`: many parallel requests to small files.
- `mixed-page`: `index.html` + related small and medium resources.
- `large-file`: large single object download.

Traffic note:
- `scripts/run_experiment.sh` uses per-workload request counts.
- Defaults: `REQUESTS_SMALL_STATIC=1000`, `REQUESTS_MIXED_PAGE=1000`, `REQUESTS_LARGE_FILE=20`.
- Override via env vars, for example:
```bash
REQUESTS_LARGE_FILE=10 REPEATS=3 ./scripts/run_experiment.sh
```

## CSV Format

Raw CSV: `results/raw/results_raw.csv`

Columns:

- protocol
- scenario
- delay_ms
- jitter_ms
- loss_percent
- workload
- run
- requests
- concurrency
- successful_requests
- failed_requests
- avg_latency_ms
- p50_latency_ms
- p95_latency_ms
- p99_latency_ms
- throughput_rps
- total_time_ms
- error_rate

Summary CSV: `results/summary/results_summary.csv`

## Typical Errors

- `curl` has no HTTP/3 support in `curl -V` output.
- UDP `443` is not mapped to server container.
- HTTP/3 fallback to HTTP/2 (must use `curl --http3-only` to prevent fallback).
- `tc/netem` not applied because of missing `NET_ADMIN`.
- `tc qdisc` operations fail due to insufficient permissions.

## Notes

- TLS uses Caddy internal CA; client requests use `-k`.
- HTTP/2 and HTTP/3 are tested forcefully (`--alpn-list=h2|h3` for h2load, `--http3-only` for curl check).
- Re-running `analyze.py` does not delete raw CSV.
