#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT=${OUT:-"$ROOT/results/nthu_adaptive_p2_summary.csv"}
ATTEMPTS_OUT=${ATTEMPTS_OUT:-"$ROOT/results/nthu_adaptive_p2_attempts_summary.csv"}
ADAPTIVE_VARIANTS=${ADAPTIVE_VARIANTS:-}
ADAPTIVE_VARIANTS_FILE=${ADAPTIVE_VARIANTS_FILE:-}
RUN_TAG=${RUN_TAG:-$(basename "${OUT%.csv}")}
NTHU_OPENMP=${NTHU_OPENMP:-ON}

if [[ -n "$ADAPTIVE_VARIANTS_FILE" ]]; then
  ADAPTIVE_VARIANTS=$(cat "$ADAPTIVE_VARIANTS_FILE")
fi

if [[ -z "$ADAPTIVE_VARIANTS" ]]; then
  ADAPTIVE_VARIANTS=$'nthu_adaptive_p2|adaptec1*.gr|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=1400;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=1200;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=800;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=240|\nnthu_adaptive_p2_dogleg|adaptec2*.gr|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=245 --p3-init-box-size=20 --p3-box-expand-size=30;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=225;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=200|NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=500\nnthu_adaptive_p2_dogleg|adaptec3*.gr|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=4000;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=3200;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=2800;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=2400;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=1200|NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=1'
fi

mkdir -p "$(dirname "$OUT")"
: > "$OUT"
: > "$ATTEMPTS_OUT"
first=1
attempts_first=1
openmp_built=${SKIP_INITIAL_BUILD:-0}

append_summary() {
  local summary=$1
  local dest=$2
  local final_label=${3:-}
  local dest_first_ref=$4

  [[ -f "$summary" ]] || return 0
  if [[ "${!dest_first_ref}" == 1 ]]; then
    head -n 1 "$summary" > "$dest"
    printf -v "$dest_first_ref" '%s' 0
  fi
  if [[ -n "$final_label" ]]; then
    tail -n +2 "$summary" | awk -F, -v OFS=, -v label="$final_label" 'NF { $1=label; print }' >> "$dest"
  else
    tail -n +2 "$summary" >> "$dest"
  fi
}

summary_overflow() {
  local summary=$1
  awk -F, 'NR==2 { print $7 }' "$summary"
}

summary_status() {
  local summary=$1
  awk -F, 'NR==2 { print $3 }' "$summary"
}

while IFS='|' read -r label bench_pattern args_list env_assignments; do
  [[ -n "${label:-}" ]] || continue
  [[ "${label:0:1}" == "#" ]] && continue

  safe_pattern=${bench_pattern//[^[:alnum:]]/_}
  safe_run_tag=${RUN_TAG//[^[:alnum:]_.-]/_}
  remaining=${args_list:-}
  attempt=0
  selected_summary=
  last_summary=

  while :; do
    if [[ "$remaining" == *";;"* ]]; then
      extra_args=${remaining%%;;*}
      remaining=${remaining#*;;}
    else
      extra_args=$remaining
      remaining=
    fi
    attempt=$((attempt + 1))

    result_dir="$ROOT/results/${safe_run_tag}_${label}_${safe_pattern}_try${attempt}"
    attempt_label="${label}_try${attempt}"
    skip_build=0
    if [[ "$openmp_built" == 1 ]]; then
      skip_build=1
    fi

    echo "==> $label $bench_pattern try${attempt}: ${extra_args:-<default>}"
    env \
      ${env_assignments:-} \
      NTHU_OPENMP="$NTHU_OPENMP" \
      ROUTER_LABEL="$attempt_label" \
      RESULT_DIR="$result_dir" \
      BENCH_PATTERN="$bench_pattern" \
      EVALUATOR="${EVALUATOR:-lab2}" \
      OMP_NUM_THREADS="${OMP_NUM_THREADS:-4}" \
      SKIP_BUILD="$skip_build" \
      NTHU_EXTRA_ARGS="${extra_args:-}" \
      bash "$ROOT/scripts/run_nthu_ispd08.sh"
    openmp_built=1

    summary="$result_dir/summary.csv"
    last_summary=$summary
    append_summary "$summary" "$ATTEMPTS_OUT" "" attempts_first

    status=$(summary_status "$summary")
    overflow=$(summary_overflow "$summary")
    if [[ "$status" == ok && "$overflow" == 0 ]]; then
      selected_summary=$summary
      echo "selected $label $bench_pattern try${attempt} (overflow=0)"
      break
    fi
    echo "rejected $label $bench_pattern try${attempt}: status=$status overflow=$overflow"

    [[ -n "$remaining" ]] || break
  done

  append_summary "${selected_summary:-$last_summary}" "$OUT" "$label" first
done <<< "$ADAPTIVE_VARIANTS"

echo "wrote $OUT"
echo "wrote $ATTEMPTS_OUT"
