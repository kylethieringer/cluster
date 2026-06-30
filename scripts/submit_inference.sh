#!/usr/bin/env bash
# Submit a SLURM job array that runs SLEAP inference -- one task per video.
#
# Usage:
#   scripts/submit_inference.sh [--dry-run] [--config FILE] [--force]
#
#   --dry-run    Build the manifest and print the sbatch command without submitting.
#   --config F   Use config file F (default: config/inference[.local].yaml).
#   --force      Include videos even if their output .slp already exists.
#
# Reads everything else from the config file. Run from a Hyak login node.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

DRY_RUN=0
FORCE=0
CONFIG_ARG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --force)   FORCE=1 ;;
        --config)  CONFIG_ARG="${2:?--config needs a path}"; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

load_config "$CONFIG_ARG"

# --- validation -------------------------------------------------------------
[[ "$ACCOUNT" != "CHANGE_ME" ]] || die "set ACCOUNT in $CONFIG_FILE (see 'groups')"
[[ -d "$RAW_DIR" ]] || die "RAW_DIR does not exist: $RAW_DIR"
for m in "${MODEL_PATHS[@]}"; do
    [[ -e "$m" ]] || die "model path does not exist: $m"
done
if [[ ! -f "$SLEAP_SIF" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "WARN: image not found (ok for --dry-run): $SLEAP_SIF" >&2
    else
        die "image not found: $SLEAP_SIF (run scripts/build_sleap_sif.sh)"
    fi
fi

# --- enumerate videos, skipping already-done ones ---------------------------
# Videos live one folder deep: RAW_DIR/<exptID>/<video>. Glob across all
# experiment subdirectories.
shopt -s nullglob
all_videos=("$RAW_DIR"/*/$VIDEO_GLOB)
shopt -u nullglob
[[ ${#all_videos[@]} -gt 0 ]] || die "no videos matching $RAW_DIR/*/$VIDEO_GLOB"

todo_videos=()
skipped=0
for v in "${all_videos[@]}"; do
    out="$(out_path_for "$v")"
    if [[ "$FORCE" -ne 1 && -s "$out" ]]; then
        skipped=$((skipped + 1))
        continue
    fi
    todo_videos+=("$v")
done

echo "Videos found: ${#all_videos[@]}  |  already done (skipped): $skipped  |  to process: ${#todo_videos[@]}"
[[ ${#todo_videos[@]} -gt 0 ]] || { echo "Nothing to do. Use --force to reprocess."; exit 0; }

# --- write manifest ---------------------------------------------------------
mkdir -p "$LOG_DIR/manifests"
manifest="$LOG_DIR/manifests/videos_$(date +%Y%m%d_%H%M%S).txt"
printf '%s\n' "${todo_videos[@]}" > "$manifest"
echo "Manifest: $manifest"

# --- assemble sbatch command ------------------------------------------------
n=${#todo_videos[@]}
array_spec="1-${n}"
[[ -n "${MAX_CONCURRENT:-}" ]] && array_spec+="%${MAX_CONCURRENT}"

slurm_script="$(repo_root)/scripts/inference_array.slurm"
sbatch_cmd=(sbatch
    -A "$ACCOUNT"
    -p "$PARTITION"
    --array="$array_spec"
    -N 1 -n 1
    -c "$CPUS"
    --mem "$MEM"
    -t "$TIME"
)
# GPU_SPEC may contain a flag with '=' (e.g. --gpus=1); split on whitespace.
# shellcheck disable=SC2206
sbatch_cmd+=(${GPU_SPEC})
[[ "${REQUEUE:-0}" -eq 1 ]] && sbatch_cmd+=(--requeue)
sbatch_cmd+=(-o "$LOG_DIR/sleap-%A_%a.out" -e "$LOG_DIR/sleap-%A_%a.err")
sbatch_cmd+=("$slurm_script" "$manifest")

# CONFIG_FILE is exported by load_config so the array tasks read the same config.
echo
echo "sbatch command:"
printf '  %q' "${sbatch_cmd[@]}"; echo

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo
    echo "[dry-run] not submitting. Manifest written above."
    exit 0
fi

mkdir -p "$LOG_DIR"
"${sbatch_cmd[@]}"
echo
echo "Submitted. Monitor with:  squeue --me    |    sacct -j <jobid>"
