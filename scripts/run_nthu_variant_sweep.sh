#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT=${OUT:-"$ROOT/results/nthu_variant_sweep_summary.csv"}
VARIANTS=${VARIANTS:-}
VARIANTS_FILE=${VARIANTS_FILE:-}
RESULT_SUFFIX=${RESULT_SUFFIX:-adaptec1}
NTHU_OPENMP=${NTHU_OPENMP:-ON}

if [[ -n "$VARIANTS_FILE" ]]; then
  VARIANTS=$(cat "$VARIANTS_FILE")
fi

if [[ -z "$VARIANTS" ]]; then
  cat >&2 <<'EOF'
VARIANTS is required.
Format: one variant per line:
  label|NTHU_EXTRA_ARGS|ENV_ASSIGNMENTS

Example:
  VARIANTS=$'box5_5|--p2-init-box-size=5 --p2-box-expand-size=5|\nbox8_8|--p2-init-box-size=8 --p2-box-expand-size=8|NTHU_PROFILE=1'
EOF
  exit 2
fi

mkdir -p "$(dirname "$OUT")"
: > "$OUT"
first=1
openmp_built=${SKIP_INITIAL_BUILD:-0}

while IFS='|' read -r label extra_args env_assignments; do
  [[ -n "${label:-}" ]] || continue
  [[ "${label:0:1}" == "#" ]] && continue

  result_dir="$ROOT/results/${label}_${RESULT_SUFFIX}"
  skip_build=0
  if [[ "$openmp_built" == 1 ]]; then
    skip_build=1
  fi

  echo "==> $label"
  env \
    ${env_assignments:-} \
    NTHU_OPENMP="$NTHU_OPENMP" \
    ROUTER_LABEL="$label" \
    RESULT_DIR="$result_dir" \
    BENCH_PATTERN="${BENCH_PATTERN:-adaptec1*.gr}" \
    EVALUATOR="${EVALUATOR:-lab2}" \
    OMP_NUM_THREADS="${OMP_NUM_THREADS:-4}" \
    SKIP_BUILD="$skip_build" \
    NTHU_EXTRA_ARGS="${extra_args:-}" \
    bash "$ROOT/scripts/run_nthu_ispd08.sh"
  openmp_built=1

  summary="$result_dir/summary.csv"
  if [[ -f "$summary" ]]; then
    if [[ "$first" == 1 ]]; then
      cat "$summary" > "$OUT"
      first=0
    else
      tail -n +2 "$summary" >> "$OUT"
    fi
  fi
done <<< "$VARIANTS"

echo "wrote $OUT"
