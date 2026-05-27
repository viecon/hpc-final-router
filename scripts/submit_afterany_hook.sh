#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 JOB_ID [LABEL]" >&2
  echo "optional env: HOOK_COMMAND='command to run after the job finishes'" >&2
  exit 2
fi

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
JOB_ID=$1
LABEL=${2:-job_${JOB_ID}}
SAFE_LABEL=${LABEL//[^[:alnum:]_.-]/_}
HOOK_COMMAND=${HOOK_COMMAND:-}
HOOK_DIR="$ROOT/results/job_hooks"
mkdir -p "$HOOK_DIR" "$ROOT/logs"

HOOK_SCRIPT="$HOOK_DIR/afterany_${JOB_ID}_${SAFE_LABEL}.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'set -euo pipefail'
  printf 'cd %q\n' "$ROOT"
  printf 'target_job=%q\n' "$JOB_ID"
  printf 'label=%q\n' "$SAFE_LABEL"
  printf '%s\n' 'mkdir -p results/job_hooks'
  printf '%s\n' 'done_file="results/job_hooks/${target_job}_${label}.done"'
  printf '%s\n' 'status_file="results/job_hooks/${target_job}_${label}.sacct"'
  printf '%s\n' 'command_log="results/job_hooks/${target_job}_${label}.command.log"'
  printf '%s\n' 'date -Is > "$done_file"'
  printf '%s\n' 'sacct -j "$target_job" --format=JobID,JobName%30,State,Elapsed,ExitCode -P > "$status_file" 2>/dev/null || true'
  if [[ -n "$HOOK_COMMAND" ]]; then
    printf 'hook_command=%q\n' "$HOOK_COMMAND"
    printf '%s\n' 'bash -lc "$hook_command" > "$command_log" 2>&1 || echo "HOOK_COMMAND failed with $?" >> "$command_log"'
  fi
  printf '%s\n' 'bash scripts/refresh_indexes.sh'
  printf '%s\n' 'echo "hook completed for $target_job ($label)"'
} > "$HOOK_SCRIPT"
chmod +x "$HOOK_SCRIPT"

SBATCH_ARGS=(
  --account="${SLURM_ACCOUNT_NAME:-ACD115058}"
  --partition="${SLURM_PARTITION_NAME:-nycugpu_queue}"
  --nodes=1
  --ntasks-per-node=1
  --cpus-per-task="${HOOK_CPUS:-1}"
  --mem="${HOOK_MEM:-1G}"
  --time="${HOOK_TIME:-0-00:05:00}"
  --job-name="hook-${SAFE_LABEL:0:20}"
  --dependency="afterany:${JOB_ID}"
  --output="$ROOT/logs/hook-${SAFE_LABEL}_%j.log"
  --error="$ROOT/logs/hook-${SAFE_LABEL}_%j.err"
)

if [[ "${HOOK_GPUS:-1}" != 0 ]]; then
  SBATCH_ARGS+=(--gpus-per-node="${HOOK_GPUS:-1}")
fi

sbatch "${SBATCH_ARGS[@]}" "$HOOK_SCRIPT"
