#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <delay_ms> <jitter_ms> <loss_percent>" >&2
  exit 1
fi

DELAY_MS="$1"
JITTER_MS="$2"
LOSS_PERCENT="$3"
DEV="${NETEM_DEV:-eth0}"

tc qdisc replace dev "${DEV}" root netem delay "${DELAY_MS}ms" "${JITTER_MS}ms" loss "${LOSS_PERCENT}%"
echo "Applied netem on ${DEV}: delay=${DELAY_MS}ms jitter=${JITTER_MS}ms loss=${LOSS_PERCENT}%"
tc qdisc show dev "${DEV}"
