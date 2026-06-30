# shellcheck shell=bash
# =============================================================================
# Hyak ANTsPy motion correction -- configuration
# =============================================================================
# This is the ONE file you edit. It is sourced by scripts/submit_moco.sh and
# re-sourced inside each SLURM array task. Keep it valid bash: KEY=value, no
# spaces around '='. To keep machine-specific secrets/paths out of git, copy
# this to config/moco.config.local.sh and edit that instead -- the scripts
# prefer a *.local.sh file if it exists.
#
# This is the CPU sibling of config/inference.yaml (SLEAP). ANTs SyN
# registration is CPU-only, so there is NO GPU request here.
# =============================================================================

# -----------------------------------------------------------------------------
# Allocation (SLURM) -- which account/partition your jobs run under.
# -----------------------------------------------------------------------------
# Find your account(s) with:   groups          (lab accounts you belong to)
# See partitions/CPUs with:    sinfo -s        and   hyakalloc
# Docs: https://hyak.uw.edu/docs/compute/scheduling-jobs
ACCOUNT="psych"                      # e.g. "stf" or your lab's account (-A)

# Your cluster username, used to build the default /gscratch paths below
# (MOCO_SIF, DATA_ROOT). Defaults to your login ($USER) -- correct for almost
# everyone. Override only to point at a different/shared name, either by editing
# here or with `export USER_ID=name` before submitting.
USER_ID="${USER_ID:-$USER}"

PARTITION="ckpt-all"                 # CPU partition. "ckpt-all" = free idle
                                     # nodes (preemptible). NOTE: motion
                                     # correction is NOT checkpointed -- a
                                     # preempted task restarts the whole
                                     # experiment from scratch. For long runs a
                                     # dedicated CPU partition (e.g. "compute")
                                     # is safer; see hyakalloc for options.

CPUS=8                               # CPU cores per task (-c). ANTs/ITK threads
                                     # are pinned to this in the array script.
MEM="64G"                            # RAM per task (--mem). The driver holds the
                                     # full functional volume in memory plus a
                                     # zeros_like copy of it, so size generously.
TIME="12:00:00"                      # walltime per experiment (-t), HH:MM:SS.
                                     # SyN over every volume is slow; tune after
                                     # the first real run.

# When PARTITION is preemptible (ckpt-all), requeue preempted tasks.
# Set to 1 for ckpt-all, 0 for a dedicated partition.
REQUEUE=1

# Cap how many array tasks run at once (SLURM array "%N" throttle).
# Empty = no cap (let the scheduler decide).
MAX_CONCURRENT=20

# -----------------------------------------------------------------------------
# Container build (Apptainer image + the nre package baked into it)
# -----------------------------------------------------------------------------
# antspyx (ANTsPy) version pinned into the .sif (see containers/moco.def). Must
# be a release with a manylinux wheel for the image's Python (Ubuntu 24.04 ->
# Python 3.12). Check https://pypi.org/project/antspyx/#files if a build fails.
ANTSPY_VERSION="0.5.4"

# The motion-correction code lives in the private Ahmed-lab repo
# oahmedlab/nifty-roi-extractor (package dir `nre/`). The build script clones it
# over SSH on the host (your login-node key) at the pinned commit and copies the
# package into the image -- no in-container auth, fully reproducible. Bump
# NRE_COMMIT to pull a newer version of the lab code.
NRE_REPO="git@github.com:oahmedlab/nifty-roi-extractor.git"
NRE_COMMIT="0a1be733b937f054d9ac3416bbd0174128d118f2"

# Path to the built Apptainer image (see scripts/build_moco_sif.sh). Kept on
# /gscratch (not $HOME): the image and its build scratch are multi-GB and would
# blow the tight home quota.
MOCO_SIF="${MOCO_SIF:-/gscratch/$ACCOUNT/$USER_ID/moco_${ANTSPY_VERSION}.sif}"

# -----------------------------------------------------------------------------
# Processing parameters
# -----------------------------------------------------------------------------
# Number of leading volumes averaged into the fixed/mean brain (moco.generate_fixed).
FIXED_VOLUMES=300
# Which .nii in an experiment folder is the functional channel (preferred) and,
# as a fallback when only one channel was recorded, the structural channel.
FUNC_GLOB="*channel_2.nii"
STRUC_GLOB="*channel_1.nii"

# -----------------------------------------------------------------------------
# Data layout -- where raw .nii volumes come from and where outputs go.
# -----------------------------------------------------------------------------
# Experiments live one folder deep: each has its own subdirectory holding its
# .nii volume(s). For each experiment, motion correction writes
#   PROCESSED_DIR/<exptID>/fixed.nii            (mean/fixed brain)
#   PROCESSED_DIR/<exptID>/motion_corrected.nii (SyN-corrected functional)
# (the per-experiment subfolder is mirrored into PROCESSED_DIR).
DATA_ROOT="/gscratch/scrubbed/$USER_ID/data"   # parent of raw/ and processed/
RAW_DIR="$DATA_ROOT/raw"                  # one subfolder per experiment
PROCESSED_DIR="$DATA_ROOT/processed"      # outputs, grouped by experiment
LOG_DIR="${LOG_DIR:-$PWD/logs}"           # SLURM logs + manifests land here
