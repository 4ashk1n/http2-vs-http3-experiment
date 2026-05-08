#!/usr/bin/env bash
set -euo pipefail

TARGET_URL="${TARGET_URL:-https://server/}"

echo "== curl version =="
curl -V

if ! curl -V | grep -qiE 'http3|h3'; then
  echo "ERROR: curl does not advertise HTTP/3 support. Use a client image with HTTP/3-enabled curl." >&2
  exit 1
fi

echo "== HTTP/2 check =="
H2_HEADERS="$(mktemp)"
curl -ksS --http2 -I "${TARGET_URL}" -o "${H2_HEADERS}"
cat "${H2_HEADERS}"
if ! grep -q "HTTP/2 200" "${H2_HEADERS}"; then
  echo "ERROR: HTTP/2 check failed. Expected 'HTTP/2 200'." >&2
  exit 1
fi

echo "== HTTP/3 check =="
H3_HEADERS="$(mktemp)"
if ! curl -ksS --http3-only -I "${TARGET_URL}" -o "${H3_HEADERS}"; then
  echo "ERROR: HTTP/3 request failed. Check UDP/443 mapping and server QUIC support." >&2
  exit 1
fi
cat "${H3_HEADERS}"
if ! grep -q "HTTP/3 200" "${H3_HEADERS}"; then
  echo "ERROR: HTTP/3 check failed. Expected 'HTTP/3 200' and no fallback." >&2
  exit 1
fi

echo "Protocol checks passed."
