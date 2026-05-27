#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks results/targeted_repairs

design=benchmarks/ispd08/adaptec3.dragon70.3d.30.50.90.gr
route=results/nctu_param_sweep_a3_wl20_m5_greedy/adaptec3.dragon70.3d.30.50.90.nctu.out
out=results/targeted_repairs/nctu_a3_wl20_m5_greedy_astar.out
prefix=results/targeted_repairs/nctu_a3_wl20_m5_greedy_astar
summary=results/targeted_repairs/nctu_a3_wl20_m5_greedy_astar_summary.csv
metrics=${out%.out}.metrics.json

job=$(
  sbatch --parsable \
    --account=ACD115058 \
    --partition=nycugpu_queue \
    --nodes=1 \
    --ntasks-per-node=1 \
    --cpus-per-task=4 \
    --gpus-per-node=1 \
    --mem=32G \
    --time=0-00:20:00 \
    --job-name=astar-nctu-a3m5 \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --wrap="cd '$ROOT' && python3 scripts/targeted_astar_segment_repair.py --design '$design' --route '$route' --out '$out' --work-prefix '$prefix' --max-passes 8 --max-nets-per-edge 96 --radius 96 --allow-equal-displacement; apptainer exec router.sif python3 scripts/evaluate_route.py '$design' '$out' --evaluator lab2 --verifier external/lab2-checker/verifier.py --nthu-dir external/nthu-route > '$metrics' 2> '${out%.out}.eval' || true; apptainer exec router.sif python3 - '$metrics' '$summary' '$out' <<'PY'
import json, sys
metrics, summary, out = sys.argv[1:4]
try:
    with open(metrics, 'r', encoding='utf-8') as f:
        data = json.load(f)
    status = 'ok'
except Exception:
    data = {}
    status = 'eval_fail'
with open(summary, 'w', encoding='utf-8') as f:
    f.write('router,benchmark,status,seconds,evaluator,total_wirelength,total_overflow,max_overflow,overflowed_nets,overflowed_edges,output\n')
    f.write(','.join([
        'repair_nctu_a3_wl20_m5_astar',
        'adaptec3.dragon70.3d.30.50.90',
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

echo "$job" > results/job_hooks/submitted_repair_nctu_a3_wl20_m5_astar.jobid
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "repair-nctu-a3m5-astar-refresh" >/dev/null 2>&1 &
echo "$job"
