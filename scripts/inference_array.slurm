#!/usr/bin/env bash
#SBATCH --job-name=sleap-infer
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --output=logs/sleap-%A_%a.out
#SBATCH --error=logs/sleap-%A_%a.err
# Account, partition, GPU, cpus, mem, time, --array and --requeue are all
# supplied by scripts/submit_inference.sh at submit time so this file stays
# generic. One array task == one video.

set -euo pipefail

MANIFEST="${1:?usage: sbatch inference_array.slurm <manifest_file>}"
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
load_config   # uses $CONFIG_FILE propagated from submit_inference.sh

# --- pick this task's video -------------------------------------------------
: "${SLURM_ARRAY_TASK_ID:?must run as a SLURM array job}"
VIDEO="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$MANIFEST")"
[[ -n "$VIDEO" ]] || die "no video on manifest line ${SLURM_ARRAY_TASK_ID} of $MANIFEST"
[[ -f "$VIDEO" ]] || die "video not found: $VIDEO"

mkdir -p "$OUTPUT_DIR"
base="$(basename "$VIDEO")"
OUT="$OUTPUT_DIR/${base%.*}.predictions.slp"

echo "=== task ${SLURM_ARRAY_TASK_ID} on $(hostname) at $(date) ==="
echo "video : $VIDEO"
echo "output: $OUT"
nvidia-smi || echo "WARN: nvidia-smi unavailable (no GPU?)"

# Idempotency at the task level too: skip if output already exists.
if [[ -s "$OUT" ]]; then
    echo "output already exists, skipping: $OUT"
    exit 0
fi

APPTAINER="$(command -v apptainer || command -v singularity)" \
    || die "apptainer/singularity not found on compute node"
[[ -f "$SLEAP_SIF" ]] || die "image not found: $SLEAP_SIF (run scripts/build_sleap_sif.sh)"

# --- assemble the inference command -----------------------------------------
# -m for each configured model (top-down = centroid + centered_instance).
model_args=()
for m in "${MODEL_PATHS[@]}"; do
    model_args+=(-m "$m")
done

# Bind data locations into the container (gscratch is usually auto-mounted, but
# bind explicitly to be safe). Collect unique existing directories.
bind_dirs=("$VIDEO_DIR" "$OUTPUT_DIR")
for m in "${MODEL_PATHS[@]}"; do
    bind_dirs+=("$(dirname "$m")")
done
bind_arg=""
while IFS= read -r d; do
    [[ -d "$d" ]] && bind_arg+="${bind_arg:+,}$d"
done < <(printf '%s\n' "${bind_dirs[@]}" | sort -u)

echo "running: $TRACK_SUBCMD -i <video> ${model_args[*]} --device $DEVICE -o <out> $EXTRA_TRACK_ARGS"
# shellcheck disable=SC2086  # word-splitting of TRACK_SUBCMD/EXTRA_TRACK_ARGS is intentional
"$APPTAINER" exec --nv ${bind_arg:+--bind "$bind_arg"} "$SLEAP_SIF" \
    $TRACK_SUBCMD -i "$VIDEO" "${model_args[@]}" --device "$DEVICE" -o "$OUT" $EXTRA_TRACK_ARGS

echo "=== done task ${SLURM_ARRAY_TASK_ID} at $(date): $OUT ==="
