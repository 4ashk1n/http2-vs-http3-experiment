#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${ROOT_DIR}/data"

mkdir -p "${DATA_DIR}/small" "${DATA_DIR}/medium" "${DATA_DIR}/large"
rm -f "${DATA_DIR}/small"/* "${DATA_DIR}/medium"/* "${DATA_DIR}/large"/*

# Deterministic binary content based on SHA256 stream.
make_file() {
  local output="$1"
  local bytes="$2"
  local seed="$3"
  python3 - "$output" "$bytes" "$seed" <<'PY'
import hashlib
import sys

path = sys.argv[1]
size = int(sys.argv[2])
seed = sys.argv[3].encode()

buf = bytearray()
i = 0
while len(buf) < size:
    buf.extend(hashlib.sha256(seed + b":" + str(i).encode()).digest())
    i += 1

with open(path, "wb") as f:
    f.write(buf[:size])
PY
}

for i in $(seq -w 1 100); do
  size=$((10 * 1024 + (10#$i % 11) * 1024))
  make_file "${DATA_DIR}/small/small_${i}.bin" "${size}" "small_${i}"
done

for i in $(seq -w 1 20); do
  size=$((500 * 1024 + (10#$i % 11) * 50 * 1024))
  make_file "${DATA_DIR}/medium/medium_${i}.bin" "${size}" "medium_${i}"
done

for i in $(seq -w 1 3); do
  size=$((50 * 1024 * 1024))
  make_file "${DATA_DIR}/large/large_${i}.bin" "${size}" "large_${i}"
done

INDEX_FILE="${DATA_DIR}/index.html"
{
  echo "<!doctype html>"
  echo "<html><head><meta charset=\"utf-8\"><title>HTTP2/HTTP3 experiment</title></head><body>"
  echo "<h1>Experiment resource index</h1>"
  echo "<h2>Small</h2>"
  for i in $(seq -w 1 100); do
    echo "<a href=\"/small/small_${i}.bin\">small_${i}</a><br/>"
  done
  echo "<h2>Medium</h2>"
  for i in $(seq -w 1 20); do
    echo "<a href=\"/medium/medium_${i}.bin\">medium_${i}</a><br/>"
  done
  echo "</body></html>"
} > "${INDEX_FILE}"

echo "Data generated in ${DATA_DIR}"
