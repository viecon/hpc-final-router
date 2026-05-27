#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p results logs

{
  printf "source_file,router,benchmark,status,seconds,evaluator,total_wirelength,total_overflow,max_overflow,overflowed_nets,overflowed_edges,output\n"
  find results -maxdepth 2 -type f \( -name "summary.csv" -o -name "*summary*.csv" \) | sort | while read -r f; do
    IFS= read -r header < "$f" || continue
    case "$header" in
      router,benchmark,status,seconds,evaluator,total_wirelength,total_overflow,max_overflow,overflowed_nets,overflowed_edges,output*) ;;
      *) continue ;;
    esac
    tail -n +2 "$f" | awk -v src="$f" 'NF {print src "," $0}'
  done
} > results/all_summaries_catalog.csv

if [[ -f scripts/rank_router_results.py && -f results/real_baselines_summary.csv ]]; then
  python3 scripts/rank_router_results.py \
    --catalog results/all_summaries_catalog.csv \
    --baseline results/real_baselines_summary.csv \
    --out results/legal_runtime_ranking.csv
fi

{
  printf "path,bytes,mtime\n"
  find results -maxdepth 2 -type f | sort | while read -r f; do
    stat -c "%n,%s,%y" "$f"
  done
} > results/manifest.csv

{
  printf "path,bytes,mtime\n"
  find logs -maxdepth 1 -type f | sort | while read -r f; do
    stat -c "%n,%s,%y" "$f"
  done
} > logs/manifest.csv

echo "refreshed results/all_summaries_catalog.csv"
echo "refreshed results/manifest.csv"
echo "refreshed logs/manifest.csv"
