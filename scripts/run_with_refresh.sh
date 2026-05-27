#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ $# -eq 0 ]]; then
  echo "usage: $0 COMMAND [ARG ...]" >&2
  exit 2
fi

status=0
"$@" || status=$?
bash "$ROOT/scripts/refresh_indexes.sh" || true
exit "$status"
