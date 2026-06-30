#!/usr/bin/env bash
#SBATCH --job-name=moco
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --output=logs/moco-%A_%a.out
#SBATCH --error=logs/moco-%A_%a.err
# Account, partition, cpus, mem, time, --array and --requeue are all supplied by
# scripts/submit_moco.sh at submit time so this file stays generic. CPU-only:
# ANTs SyN needs no GPU. One array task == one experiment.

set -euo pipefail

MANIFEST="${1:?usage: sbatch moco_array.slurm <manifest_file>}"
# SLURM copies this script into the job spool dir before running it, so
# ${BASH_SOURCE[0]} does NOT point at the repo. submit_moco.sh exports
# REPO_ROOT (inherited via sbatch's default --export=ALL) so we can find it.
: "${REPO_ROOT:?REPO_ROOT not set -- submit via scripts/submit_moco.sh}"
source "$REPO_ROOT/scripts/_common.sh"
load_config   # uses $CONFIG_FILE propagated from submit_moco.sh

# --- pick this task's experiment --------------------------------------------
: "${SLURM_ARRAY_TASK_ID:?must run as a SLURM array job}"
EXP_RAW="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$MANIFEST")"
[[ -n "$EXP_RAW" ]] || die "no experiment on manifest line ${SLURM_ARRAY_TASK_ID} of $MANIFEST"
[[ -d "$EXP_RAW" ]] || die "experiment folder not found: $EXP_RAW"

EXP_ID="$(basename "$EXP_RAW")"
EXP_OUT="$PROCESSED_DIR/$EXP_ID"
OUT="$EXP_OUT/motion_corrected.nii"

echo "=== task ${SLURM_ARRAY_TASK_ID} on $(hostname) at $(date) ==="
echo "experiment: $EXP_ID"
echo "raw       : $EXP_RAW"
echo "output    : $OUT"

# Idempotency at the task level too: skip if output already exists.
if [[ -s "$OUT" ]]; then
    echo "output already exists, skipping: $OUT"
    exit 0
fi

APPTAINER="$(command -v apptainer || command -v singularity)" \
    || die "apptainer/singularity not found on compute node"
[[ -f "$MOCO_SIF" ]] || die "image not found: $MOCO_SIF (run scripts/build_moco_sif.sh)"

ROOT="$(repo_root)"

# Pin ANTs/ITK threads to the cores SLURM gave us (the image default is 1).
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="${SLURM_CPUS_PER_TASK:-$CPUS}"
export APPTAINERENV_ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="$ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS"

# Create the output dir on the HOST, where gscratch is writable. This is what
# makes PROCESSED_DIR exist so the bind loop below mounts it read-write -- if we
# left run_moco.py to mkdir it inside the read-only container image, the write
# fails with "Errno 30 Read-only file system".
mkdir -p "$EXP_OUT"

# Bind the repo (for run_moco.py) and the data tree into the container. gscratch
# is usually auto-mounted, but bind explicitly to be safe. CPU-only -> no --nv.
bind_dirs=("$ROOT" "$RAW_DIR" "$PROCESSED_DIR")
bind_arg=""
while IFS= read -r d; do
    [[ -d "$d" ]] && bind_arg+="${bind_arg:+,}$d"
done < <(printf '%s\n' "${bind_dirs[@]}" | sort -u)

echo "running: run_moco.py --raw $EXP_RAW --out $EXP_OUT --fixed-volumes $FIXED_VOLUMES"
"$APPTAINER" exec ${bind_arg:+--bind "$bind_arg"} "$MOCO_SIF" \
    python3 "$ROOT/scripts/run_moco.py" \
        --raw "$EXP_RAW" --out "$EXP_OUT" \
        --fixed-volumes "$FIXED_VOLUMES" \
        --func-glob "$FUNC_GLOB" --struc-glob "$STRUC_GLOB"

echo "=== done task ${SLURM_ARRAY_TASK_ID} at $(date): $OUT ==="
