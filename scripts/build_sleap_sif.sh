#!/usr/bin/env bash
# Build the SLEAP Apptainer image (.sif) from containers/sleap.def.
#
# Usage:
#   scripts/build_sleap_sif.sh [--force]
#
# Reads SLEAP_VERSION and SLEAP_SIF from the config file. Idempotent: skips the
# build if the .sif already exists unless --force is given. Run this on a Hyak
# compute node (apptainer build can be heavy); a CPU node is fine for building.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
        *) die "unknown argument: $arg" ;;
    esac
done

load_config
DEF_FILE="$(repo_root)/containers/sleap.def"

[[ -f "$DEF_FILE" ]] || die "definition file missing: $DEF_FILE"
command -v apptainer >/dev/null 2>&1 || command -v singularity >/dev/null 2>&1 \
    || die "apptainer/singularity not found. On Hyak: 'module load apptainer' (or it may be on PATH)."
APPTAINER="$(command -v apptainer || command -v singularity)"

if [[ -f "$SLEAP_SIF" && "$FORCE" -ne 1 ]]; then
    echo "Image already exists: $SLEAP_SIF (use --force to rebuild)"
    exit 0
fi

mkdir -p "$(dirname "$SLEAP_SIF")"
echo "Building $SLEAP_SIF"
echo "  from:    $DEF_FILE"
echo "  version: SLEAP $SLEAP_VERSION"
"$APPTAINER" build --build-arg "SLEAP_VERSION=${SLEAP_VERSION}" "$SLEAP_SIF" "$DEF_FILE"

cat <<EOF

Done: $SLEAP_SIF

Verify GPU access from inside a GPU allocation, e.g.:
  salloc -A "$ACCOUNT" -p "$PARTITION" $GPU_SPEC -c 2 --mem 8G -t 00:20:00
  $APPTAINER exec --nv "$SLEAP_SIF" python3 -c "import torch; print(torch.cuda.is_available())"
  $APPTAINER exec --nv "$SLEAP_SIF" nvidia-smi
EOF
