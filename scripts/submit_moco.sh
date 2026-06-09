#!/usr/bin/env bash
# Submit a SLURM job array that runs ANTsPy motion correction -- one task per
# experiment.
#
# Usage:
#   scripts/submit_moco.sh [--dry-run] [--config FILE] [--force]
#
#   --dry-run    Build the manifest and print the sbatch command without submitting.
#   --config F   Use config file F (default: config/moco.config[.local].sh).
#   --force      Include experiments even if their motion_corrected.nii exists.
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

# Resolve the moco config: explicit --config, else a *.local.sh override, else
# the tracked default. (load_config's built-in default targets the SLEAP config.)
ROOT="$(repo_root)"
if [[ -z "$CONFIG_ARG" ]]; then
    if [[ -f "$ROOT/config/moco.config.local.sh" ]]; then
        CONFIG_ARG="$ROOT/config/moco.config.local.sh"
    else
        CONFIG_ARG="$ROOT/config/moco.config.sh"
    fi
fi
load_config "$CONFIG_ARG"

# --- validation -------------------------------------------------------------
[[ "$ACCOUNT" != "CHANGE_ME" ]] || die "set ACCOUNT in $CONFIG_FILE (see 'groups')"
[[ -d "$RAW_DIR" ]] || die "RAW_DIR does not exist: $RAW_DIR"
if [[ ! -f "$MOCO_SIF" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "WARN: image not found (ok for --dry-run): $MOCO_SIF" >&2
    else
        die "image not found: $MOCO_SIF (run scripts/build_moco_sif.sh)"
    fi
fi

# --- enumerate experiments, skipping already-done ones ----------------------
# Experiments live one folder deep: each subdir of RAW_DIR is one experiment.
shopt -s nullglob
all_exps=("$RAW_DIR"/*/)
shopt -u nullglob
[[ ${#all_exps[@]} -gt 0 ]] || die "no experiment subfolders in $RAW_DIR"

todo_exps=()
skipped=0
for d in "${all_exps[@]}"; do
    d="${d%/}"                                  # strip trailing slash
    exp_id="$(basename "$d")"
    out="$PROCESSED_DIR/$exp_id/motion_corrected.nii"
    if [[ "$FORCE" -ne 1 && -s "$out" ]]; then
        skipped=$((skipped + 1))
        continue
    fi
    todo_exps+=("$d")
done

echo "Experiments found: ${#all_exps[@]}  |  already done (skipped): $skipped  |  to process: ${#todo_exps[@]}"
[[ ${#todo_exps[@]} -gt 0 ]] || { echo "Nothing to do. Use --force to reprocess."; exit 0; }

# --- write manifest ---------------------------------------------------------
mkdir -p "$LOG_DIR/manifests"
manifest="$LOG_DIR/manifests/moco_$(date +%Y%m%d_%H%M%S).txt"
printf '%s\n' "${todo_exps[@]}" > "$manifest"
echo "Manifest: $manifest"

# --- assemble sbatch command ------------------------------------------------
n=${#todo_exps[@]}
array_spec="1-${n}"
[[ -n "${MAX_CONCURRENT:-}" ]] && array_spec+="%${MAX_CONCURRENT}"

slurm_script="$ROOT/scripts/moco_array.slurm"
sbatch_cmd=(sbatch
    -A "$ACCOUNT"
    -p "$PARTITION"
    --array="$array_spec"
    -N 1 -n 1
    -c "$CPUS"
    --mem "$MEM"
    -t "$TIME"
)
[[ "${REQUEUE:-0}" -eq 1 ]] && sbatch_cmd+=(--requeue)
sbatch_cmd+=(-o "$LOG_DIR/moco-%A_%a.out" -e "$LOG_DIR/moco-%A_%a.err")
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
