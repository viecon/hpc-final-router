#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks results/targeted_repairs/a5_fast_a1

design=benchmarks/ispd08/adaptec5.mfar50.3d.50.20.100.gr
route=results/nthu_a5_fast_a1_style_nthu_adaptec5_self_probe/adaptec5.mfar50.3d.50.20.100.nthu.out
out=results/targeted_repairs/a5_fast_a1/repaired.out
prefix=results/targeted_repairs/a5_fast_a1/repair
metrics=results/targeted_repairs/a5_fast_a1/repaired.metrics.json
summary=results/a5_fast_a1_repair_summary.csv

job=$(
  sbatch --parsable \
    --account=ACD115058 \
    --partition=nycugpu_queue \
    --nodes=1 \
    --ntasks-per-node=1 \
    --cpus-per-task=4 \
    --gpus-per-node=1 \
    --mem=64G \
    --time=0-00:30:00 \
    --job-name=a5-fast-repair \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --wrap="cd '$ROOT' && python3 scripts/targeted_edge_split_fast_repair.py --design '$design' --route '$route' --out '$out' --work-prefix '$prefix' --max-passes 12 --max-nets-per-edge 256; apptainer exec router.sif python3 scripts/evaluate_route.py '$design' '$out' --evaluator lab2 --verifier external/lab2-checker/verifier.py --nthu-dir external/nthu-route > '$metrics' 2> '${out%.out}.eval' || true; python3 - '$metrics' '$summary' '$out' <<'PY'
import json, sys
metrics, summary, out = sys.argv[1:4]
data = {}
try:
    with open(metrics, encoding='utf-8') as f:
        data = json.load(f)
except Exception:
    pass
with open(summary, 'w', encoding='utf-8') as f:
    f.write('router,benchmark,status,seconds,evaluator,total_wirelength,total_overflow,max_overflow,overflowed_nets,overflowed_edges,output\n')
    status = 'ok' if data else 'eval_fail'
    f.write(','.join([
        'nthu_a5_fast_a1_edge_split_repair',
        'adaptec5.mfar50.3d.50.20.100',
        status,
        'NA',
        str(data.get('evaluator', 'NA')),
        str(data.get('total_wirelength', 'NA')),
        str(data.get('total_overflow', 'NA')),
        str(data.get('max_overflow', 'NA')),
        str(data.get('overflowed_nets', 'NA')),
        str(data.get('overflowed_edges', 'NA')),
        out,
    ]) + '\n')
PY
bash scripts/refresh_indexes.sh"
)

echo "$job" > results/job_hooks/submitted_a5_fast_output_repair.jobid
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "a5_fast_output_repair-refresh" >/dev/null 2>&1 &
echo "$job"
