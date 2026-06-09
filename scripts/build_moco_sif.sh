#!/usr/bin/env bash
# Build the ANTsPy motion-correction Apptainer image (.sif) from
# containers/moco.def.
#
# Usage:
#   scripts/build_moco_sif.sh [--force]
#
# Reads ANTSPY_VERSION, MOCO_SIF, NRE_REPO and NRE_COMMIT from the config file.
# Before building it stages the private nre package: it clones NRE_REPO over SSH
# (using your host/login-node key) at NRE_COMMIT into containers/.nre-src so the
# def's %files step can copy it in -- no auth happens inside the container build.
# Idempotent: skips the build if the .sif already exists unless --force is given.
# Run this on a Hyak compute node (a CPU node is fine -- no GPU needed to build).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) die "unknown argument: $arg" ;;
    esac
done

# moco has its own config; prefer a *.local.sh override like the other scripts.
ROOT="$(repo_root)"
if [[ -z "${CONFIG_FILE:-}" ]]; then
    if [[ -f "$ROOT/config/moco.config.local.sh" ]]; then
        CONFIG_FILE="$ROOT/config/moco.config.local.sh"
    else
        CONFIG_FILE="$ROOT/config/moco.config.sh"
    fi
fi
load_config "$CONFIG_FILE"

DEF_FILE="$ROOT/containers/moco.def"
[[ -f "$DEF_FILE" ]] || die "definition file missing: $DEF_FILE"
command -v apptainer >/dev/null 2>&1 || command -v singularity >/dev/null 2>&1 \
    || die "apptainer/singularity not found. On Hyak: 'module load apptainer' (or it may be on PATH)."
APPTAINER="$(command -v apptainer || command -v singularity)"

if [[ -f "$MOCO_SIF" && "$FORCE" -ne 1 ]]; then
    echo "Image already exists: $MOCO_SIF (use --force to rebuild)"
    exit 0
fi

command -v git >/dev/null 2>&1 || die "git not found (needed to stage the nre package)"

# --- stage the private nre package on the host (no in-container auth) ---------
# %files in moco.def copies containers/.nre-src/nre into the image. Clone fresh
# at the pinned commit so the baked-in package is reproducible.
NRE_SRC="$ROOT/containers/.nre-src"
echo "Staging nre package: $NRE_REPO @ ${NRE_COMMIT:0:12}"
rm -rf "$NRE_SRC"
git clone --quiet "$NRE_REPO" "$NRE_SRC" \
    || die "failed to clone $NRE_REPO (SSH key set up for github? try: ssh -T git@github.com)"
git -C "$NRE_SRC" checkout --quiet "$NRE_COMMIT" \
    || die "failed to checkout NRE_COMMIT=$NRE_COMMIT in $NRE_SRC"
[[ -d "$NRE_SRC/nre" ]] || die "expected package dir not found: $NRE_SRC/nre"

mkdir -p "$(dirname "$MOCO_SIF")"

# Apptainer extracts the wheel set into its scratch dir during %post and packs a
# squashfs -- many small files that crawl on /gscratch (Lustre). A node-local
# SSD (/scr) is far faster, so prefer one for the build's tmp + cache; the final
# .sif still lands on $MOCO_SIF. We only use a candidate if it is writable AND
# not tmpfs: a RAM-backed /tmp fills memory and the build is OOM-killed (exit
# 137 / "Killed"). If none qualifies, fall back to scratch next to the output.
# Overrides: set BUILD_SCRATCH to force a base dir, or APPTAINER_TMPDIR/
# APPTAINER_CACHEDIR to control the paths outright.
SIF_DIR="$(dirname "$MOCO_SIF")"

# Echo a writable, non-tmpfs node-local scratch dir, or return non-zero.
pick_scratch_base() {
    local cand
    for cand in "${BUILD_SCRATCH:-}" /scr /scratch /tmp; do
        [[ -n "$cand" && -d "$cand" ]] || continue
        case "$(stat -f -c %T "$cand" 2>/dev/null)" in
            tmpfs|ramfs) continue ;;   # RAM-backed -> OOM risk, skip
        esac
        local mine="$cand/$USER/apptainer-build"
        if mkdir -p "$mine" 2>/dev/null && [[ -w "$mine" ]]; then
            printf '%s\n' "$mine"
            return 0
        fi
    done
    return 1
}

if [[ -n "${APPTAINER_TMPDIR:-}" ]]; then
    BUILD_SCRATCH_DIR="$(dirname "$APPTAINER_TMPDIR")"   # caller chose; respect it
elif SCRATCH_BASE="$(pick_scratch_base)"; then
    BUILD_SCRATCH_DIR="$SCRATCH_BASE"
    echo "Using node-local build scratch: $BUILD_SCRATCH_DIR"
else
    BUILD_SCRATCH_DIR="$SIF_DIR/.apptainer-build"
    echo "No node-local scratch found; building on $BUILD_SCRATCH_DIR (slower on Lustre)"
fi

export APPTAINER_TMPDIR="${APPTAINER_TMPDIR:-$BUILD_SCRATCH_DIR/tmp}"
export APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-$BUILD_SCRATCH_DIR/cache}"
# Singularity-named fallbacks in case the runtime is the singularity binary.
export SINGULARITY_TMPDIR="${SINGULARITY_TMPDIR:-$APPTAINER_TMPDIR}"
export SINGULARITY_CACHEDIR="${SINGULARITY_CACHEDIR:-$APPTAINER_CACHEDIR}"
mkdir -p "$APPTAINER_TMPDIR" "$APPTAINER_CACHEDIR"

echo "Building $MOCO_SIF"
echo "  from:    $DEF_FILE"
echo "  antspyx: $ANTSPY_VERSION"
echo "  nre:     ${NRE_COMMIT:0:12}"
echo "  tmpdir:  $APPTAINER_TMPDIR"
echo "  cache:   $APPTAINER_CACHEDIR"
echo
echo "NOTE: build inside an allocation (not a login node), e.g."
echo "  salloc -A $ACCOUNT -p $PARTITION -c 4 --mem 16G -t 01:00:00"
# %files paths in the def are relative to the def's directory, so build from there.
( cd "$ROOT/containers" \
    && "$APPTAINER" build --build-arg "ANTSPY_VERSION=${ANTSPY_VERSION}" "$MOCO_SIF" "$DEF_FILE" )

cat <<EOF

Done: $MOCO_SIF

Verify the environment:
  $APPTAINER exec "$MOCO_SIF" python3 -c "import ants; from nre import io, moco, roi; print(ants.__version__)"
EOF
