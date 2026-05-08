#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
RAW_DIR="${RESULTS_DIR}/raw"
RAW_CSV="${RAW_DIR}/results_raw.csv"
ANALYZE_SCRIPT="${ROOT_DIR}/scripts/analyze.py"

# Per-workload request counts. Keep latency-focused workloads high, cap large-file traffic.
REQUESTS_SMALL_STATIC="${REQUESTS_SMALL_STATIC:-1000}"
REQUESTS_MIXED_PAGE="${REQUESTS_MIXED_PAGE:-1000}"
REQUESTS_LARGE_FILE="${REQUESTS_LARGE_FILE:-20}"
CONCURRENCY_LIST=(10 50 100)
REPEATS="${REPEATS:-5}"
TARGET_HOST="${TARGET_HOST:-server}"
TARGET_URL="https://${TARGET_HOST}/"

QUICK_MODE="false"
if [[ "${1:-}" == "--quick" ]]; then
  QUICK_MODE="true"
  CONCURRENCY_LIST=(10)
  REPEATS=2
fi

SCENARIOS=(
  "S1,20,0,0"
  "S2,50,5,0.5"
  "S3,100,10,1"
  "S4,150,20,2"
  "S5,200,30,5"
)

if [[ "${QUICK_MODE}" == "true" ]]; then
  SCENARIOS=(
    "S1,20,0,0"
    "S3,100,10,1"
  )
fi

WORKLOADS_CSV="${WORKLOADS_CSV:-small-static,mixed-page,large-file}"
IFS=',' read -r -a WORKLOADS <<< "${WORKLOADS_CSV}"
if [[ "${QUICK_MODE}" == "true" ]]; then
  WORKLOADS=("small-static")
fi

cleanup() {
  "${ROOT_DIR}/scripts/clear_netem.sh" || true
}
trap cleanup EXIT INT TERM

mkdir -p "${RAW_DIR}" "${RESULTS_DIR}/summary" "${RESULTS_DIR}/plots"

if [[ ! -f "${RAW_CSV}" ]]; then
  cat > "${RAW_CSV}" <<'CSV'
protocol,scenario,delay_ms,jitter_ms,loss_percent,workload,run,requests,concurrency,successful_requests,failed_requests,avg_latency_ms,p50_latency_ms,p95_latency_ms,p99_latency_ms,throughput_rps,total_time_ms,error_rate
CSV
fi

build_input_file() {
  local workload="$1"
  local file
  file="$(mktemp)"

  case "${workload}" in
    small-static)
      for i in $(seq -w 1 100); do
        echo "${TARGET_URL}small/small_${i}.bin" >> "${file}"
      done
      ;;
    mixed-page)
      echo "${TARGET_URL}index.html" >> "${file}"
      for i in $(seq -w 1 50); do
        echo "${TARGET_URL}small/small_${i}.bin" >> "${file}"
      done
      for i in $(seq -w 1 10); do
        echo "${TARGET_URL}medium/medium_${i}.bin" >> "${file}"
      done
      ;;
    large-file)
      local large_rel="large/large_01.bin"
      if [[ ! -f "${ROOT_DIR}/data/${large_rel}" ]]; then
        local first_large
        first_large="$(find "${ROOT_DIR}/data/large" -maxdepth 1 -type f -name 'large_*.bin' | sort | head -n 1 || true)"
        if [[ -z "${first_large}" ]]; then
          echo "ERROR: no large files found in ${ROOT_DIR}/data/large. Run scripts/generate_data.sh first." >&2
          exit 1
        fi
        large_rel="large/$(basename "${first_large}")"
      fi
      echo "${TARGET_URL}${large_rel}" >> "${file}"
      ;;
    *)
      echo "Unknown workload: ${workload}" >&2
      exit 1
      ;;
  esac

  echo "${file}"
}

parse_h2load() {
  local output_file="$1"
  local log_file="$2"
  local expected_requests="$3"
  python3 - "$output_file" "$log_file" "$expected_requests" <<'PY'
import math
import re
import sys
from pathlib import Path

out_text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore")
log_path = Path(sys.argv[2])
expected = int(sys.argv[3])

latencies_ms = []
successful = 0
completed = 0

if log_path.exists():
    for line in log_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        try:
            status = int(parts[1])
            duration_us = float(parts[2])
        except ValueError:
            continue
        completed += 1
        latencies_ms.append(duration_us / 1000.0)
        if 200 <= status < 400:
            successful += 1

failed = max(expected - successful, 0)

def pct(values, percentile):
    if not values:
        return ""
    values = sorted(values)
    idx = max(0, min(len(values) - 1, math.ceil((percentile / 100.0) * len(values)) - 1))
    return f"{values[idx]:.3f}"

avg = f"{(sum(latencies_ms) / len(latencies_ms)):.3f}" if latencies_ms else ""
p50 = pct(latencies_ms, 50)
p95 = pct(latencies_ms, 95)
p99 = pct(latencies_ms, 99)

unit_factor = {"us": 0.001, "ms": 1.0, "s": 1000.0, "m": 60000.0, "h": 3600000.0}
finished = re.search(r"finished in\s+([0-9]*\.?[0-9]+)(us|ms|s|m|h),\s+([0-9]*\.?[0-9]+)\s+req/s", out_text)
if finished:
    total_ms = f"{float(finished.group(1)) * unit_factor[finished.group(2)]:.3f}"
    rps = finished.group(3)
else:
    total_ms = ""
    rps = ""

print(",".join([
    str(successful),
    str(failed),
    avg,
    p50,
    p95,
    p99,
    rps,
    total_ms,
]))
PY
}

run_single() {
  local protocol="$1"
  local scenario="$2"
  local delay_ms="$3"
  local jitter_ms="$4"
  local loss_percent="$5"
  local workload="$6"
  local run_id="$7"
  local concurrency="$8"

  local h2load_protocol
  case "${protocol}" in
    h2) h2load_protocol="--alpn-list=h2" ;;
    h3) h2load_protocol="--alpn-list=h3" ;;
    *) echo "Unknown protocol ${protocol}" >&2; exit 1 ;;
  esac

  local requests
  case "${workload}" in
    small-static) requests="${REQUESTS_SMALL_STATIC}" ;;
    mixed-page) requests="${REQUESTS_MIXED_PAGE}" ;;
    large-file) requests="${REQUESTS_LARGE_FILE}" ;;
    *) echo "Unknown workload: ${workload}" >&2; exit 1 ;;
  esac

  local input_file
  input_file="$(build_input_file "${workload}")"

  # h2load requires requests >= clients; clamp concurrency for small request budgets.
  local effective_concurrency="${concurrency}"
  if (( effective_concurrency > requests )); then
    effective_concurrency="${requests}"
  fi

  local out_file
  out_file="$(mktemp)"
  local log_file
  log_file="$(mktemp)"

  set +e
  h2load "${h2load_protocol}" -n "${requests}" -c "${effective_concurrency}" -m "${effective_concurrency}" \
    -i "${input_file}" --log-file="${log_file}" "${TARGET_URL}" > "${out_file}" 2>&1
  local h2load_rc=$?
  set -e

  local parsed
  if [[ ${h2load_rc} -eq 0 ]]; then
    parsed="$(parse_h2load "${out_file}" "${log_file}" "${requests}")"
  else
    parsed="0,${requests},,,,,,"
  fi

  IFS=',' read -r successful failed avg p50 p95 p99 rps total_ms <<< "${parsed}"

  if [[ -z "${successful}" ]]; then successful="0"; fi
  if [[ -z "${failed}" ]]; then failed="${requests}"; fi

  local error_rate
  error_rate="$(python3 - <<PY
req=${requests}
fail=int('${failed}' or 0)
print(f"{(fail/req):.6f}")
PY
)"

  printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
    "${protocol}" "${scenario}" "${delay_ms}" "${jitter_ms}" "${loss_percent}" "${workload}" "${run_id}" \
    "${requests}" "${concurrency}" "${successful}" "${failed}" "${avg}" "${p50}" "${p95}" "${p99}" \
    "${rps}" "${total_ms}" "${error_rate}" >> "${RAW_CSV}"

  if [[ ${h2load_rc} -ne 0 ]]; then
    echo "WARNING: h2load exited with code ${h2load_rc} for ${protocol}/${scenario}/${workload}/c${concurrency}/run${run_id}" >&2
    sed -n '1,20p' "${out_file}" >&2
  elif [[ "${protocol}" == "h3" && "${successful}" == "0" ]]; then
    echo "ERROR: h2load reported 0 successful requests for HTTP/3 at ${scenario}/${workload}/c${concurrency}/run${run_id}" >&2
    sed -n '1,40p' "${out_file}" >&2
    rm -f "${input_file}" "${out_file}" "${log_file}"
    exit 1
  fi

  rm -f "${input_file}" "${out_file}" "${log_file}"
}

wait_for_server() {
  for _ in $(seq 1 30); do
    if curl -ksS -I "${TARGET_URL}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "ERROR: server is not reachable at ${TARGET_URL}" >&2
  return 1
}

wait_for_server
"${ROOT_DIR}/scripts/check_protocols.sh"
"${ROOT_DIR}/scripts/clear_netem.sh"

# Ensure load generator can actually run both protocol modes before long loops.
if ! h2load --alpn-list=h2 -n 1 -c 1 "${TARGET_URL}" >/dev/null 2>&1; then
  echo "ERROR: h2load HTTP/2 smoke test failed." >&2
  exit 1
fi

if ! h2load --alpn-list=h3 -n 1 -c 1 "${TARGET_URL}" >/dev/null 2>&1; then
  echo "ERROR: h2load HTTP/3 smoke test failed. Rebuild client image with H3-enabled h2load." >&2
  exit 1
fi

for scenario in "${SCENARIOS[@]}"; do
  IFS=',' read -r sc_name delay jitter loss <<< "${scenario}"
  echo "Running scenario ${sc_name} (delay=${delay}, jitter=${jitter}, loss=${loss})"

  "${ROOT_DIR}/scripts/apply_netem.sh" "${delay}" "${jitter}" "${loss}"

  for workload in "${WORKLOADS[@]}"; do
    for conc in "${CONCURRENCY_LIST[@]}"; do
      for run in $(seq 1 "${REPEATS}"); do
        run_single "h2" "${sc_name}" "${delay}" "${jitter}" "${loss}" "${workload}" "${run}" "${conc}"
        run_single "h3" "${sc_name}" "${delay}" "${jitter}" "${loss}" "${workload}" "${run}" "${conc}"
      done
    done
  done

  "${ROOT_DIR}/scripts/clear_netem.sh"
done

python3 "${ANALYZE_SCRIPT}"
echo "Experiment finished. Raw CSV: ${RAW_CSV}"
