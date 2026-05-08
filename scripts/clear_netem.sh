#!/usr/bin/env bash
set -euo pipefail

DEV="${NETEM_DEV:-eth0}"
if tc qdisc del dev "${DEV}" root 2>/dev/null; then
  echo "Cleared netem on ${DEV}"
else
  echo "No root qdisc to clear on ${DEV}"
fi

tc qdisc show dev "${DEV}"
