# Experiment Description

## 1. Goal

Build a reproducible benchmark to compare HTTP/2 and HTTP/3 under degraded network conditions.

## 2. Hypothesis

With increasing packet loss and delay, HTTP/3 may show lower degradation in p95/p99 latency for parallel resource transfer compared to HTTP/2.

## 3. Testbed

- Server: Caddy with HTTPS, HTTP/2 and HTTP/3 enabled.
- Client: container with curl (HTTP/3-capable), h2load, tc/netem, Python.
- Data sets: deterministic static files (`small`, `medium`, `large`) and one synthetic `index.html`.

## 4. Protocols

- HTTP/2 over TCP+TLS
- HTTP/3 over QUIC/UDP+TLS

The stand enforces protocol selection and checks HTTP/3 without fallback.

## 5. Network Degradation

`tc netem` applies delay, jitter and packet loss to client-side `eth0`.
Scenarios S1..S5 cover mild to severe degradation.

## 6. Metrics

Collected per run:

- successful/failed requests
- avg latency
- p50/p95/p99 latency
- throughput (req/s)
- total time
- error rate

## 7. Limitations

- Results depend on concrete client/server implementations and versions.
- Containerized setup may differ from bare metal behavior.
- h2load HTTP/3 support must be available in built binary.

## 8. Interpretation Guidance

Do not claim that HTTP/3 is always faster. Evaluate protocol behavior per workload and per scenario. Improvements, if present, are conditional on network conditions, transfer patterns and implementation details.
