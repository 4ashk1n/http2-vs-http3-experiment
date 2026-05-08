#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
RAW_DIR="${RESULTS_DIR}/raw"
RAW_CSV="${RAW_DIR}/results_raw.csv"
ANALYZE_SCRIPT="${ROOT_DIR}/scripts/analyze.py"

REQUESTS="${REQUESTS:-1000}"
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

WORKLOADS=("small-static" "mixed-page" "large-file")
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
      echo "${TARGET_URL}large/large_01.bin" >> "${file}"
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
  python3 - "$output_file" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore")

def find(pattern, default=""):
    m = re.search(pattern, text, re.MULTILINE)
    return m.group(1) if m else default

succeeded = find(r"requests:\s*\d+ total,.*?,\s*(\d+) succeeded", "0")
failed = find(r"requests:\s*\d+ total,.*?,\s*\d+ succeeded,\s*(\d+) failed", "0")
avg = find(r"time for request:\s*([0-9]*\.?[0-9]+)ms", "")
rps = find(r"finished in\s*[0-9]*\.?[0-9]+\w*,\s*([0-9]*\.?[0-9]+) req/s", "")
total = find(r"finished in\s*([0-9]*\.?[0-9]+)(ms|s)", "")
total_unit = find(r"finished in\s*[0-9]*\.?[0-9]+(ms|s)", "ms")

p50 = find(r"^\s*50%\s*([0-9]*\.?[0-9]+)ms", "") or find(r"^\s*50\s+([0-9]*\.?[0-9]+)ms", "")
p95 = find(r"^\s*95%\s*([0-9]*\.?[0-9]+)ms", "") or find(r"^\s*95\s+([0-9]*\.?[0-9]+)ms", "")
p99 = find(r"^\s*99%\s*([0-9]*\.?[0-9]+)ms", "") or find(r"^\s*99\s+([0-9]*\.?[0-9]+)ms", "")

if total:
    total_val = float(total)
    if total_unit == "s":
        total_val *= 1000
    total_ms = f"{total_val:.3f}"
else:
    total_ms = ""

print(",".join([
    succeeded,
    failed,
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

  local alpn
  case "${protocol}" in
    h2) alpn="h2" ;;
    h3) alpn="h3" ;;
    *) echo "Unknown protocol ${protocol}" >&2; exit 1 ;;
  esac

  local input_file
  input_file="$(build_input_file "${workload}")"

  local out_file
  out_file="$(mktemp)"

  set +e
  h2load -k --alpn-list="${alpn}" -n "${REQUESTS}" -c "${concurrency}" -m "${concurrency}" -i "${input_file}" "${TARGET_URL}" > "${out_file}" 2>&1
  local h2load_rc=$?
  set -e

  local parsed
  parsed="$(parse_h2load "${out_file}")"

  IFS=',' read -r successful failed avg p50 p95 p99 rps total_ms <<< "${parsed}"

  if [[ -z "${successful}" ]]; then successful="0"; fi
  if [[ -z "${failed}" ]]; then failed="${REQUESTS}"; fi

  local error_rate
  error_rate="$(python3 - <<PY
req=${REQUESTS}
fail=int('${failed}' or 0)
print(f"{(fail/req):.6f}")
PY
)"

  printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
    "${protocol}" "${scenario}" "${delay_ms}" "${jitter_ms}" "${loss_percent}" "${workload}" "${run_id}" \
    "${REQUESTS}" "${concurrency}" "${successful}" "${failed}" "${avg}" "${p50}" "${p95}" "${p99}" \
    "${rps}" "${total_ms}" "${error_rate}" >> "${RAW_CSV}"

  if [[ ${h2load_rc} -ne 0 ]]; then
    echo "WARNING: h2load exited with code ${h2load_rc} for ${protocol}/${scenario}/${workload}/c${concurrency}/run${run_id}" >&2
  fi

  rm -f "${input_file}" "${out_file}"
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
