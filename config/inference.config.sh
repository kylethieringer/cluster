# shellcheck shell=bash
# =============================================================================
# Hyak SLEAP parallel inference -- configuration
# =============================================================================
# This is the ONE file you edit. It is sourced by scripts/submit_inference.sh
# and re-sourced inside each SLURM array task. Keep it valid bash: KEY=value,
# no spaces around '='. To keep machine-specific secrets/paths out of git,
# copy this to config/inference.config.local.sh and edit that instead -- the
# scripts prefer a *.local.sh file if it exists.
# =============================================================================

# -----------------------------------------------------------------------------
# Allocation (SLURM) -- which account/partition your jobs run under.
# -----------------------------------------------------------------------------
# Find your account(s) with:   groups          (lab accounts you belong to)
# See partitions/GPUs with:    sinfo -s        and   hyakalloc
# Docs: https://hyak.uw.edu/docs/compute/scheduling-jobs
ACCOUNT="CHANGE_ME"                  # e.g. "stf" or your lab's account (-A)
PARTITION="ckpt-all"                 # GPU partition, e.g. gpu-a100 / gpu-l40s.
                                     # "ckpt-all" = free idle GPUs (preemptible).

GPU_SPEC="--gpus=1"                  # GPU request, e.g. "--gpus=1" or
                                     # "--gres=gpu:a100:1" to pin a GPU type.
CPUS=8                               # CPU cores per task (-c)
MEM="32G"                            # RAM per task (--mem)
TIME="04:00:00"                      # walltime per video (-t), HH:MM:SS

# When PARTITION is preemptible (ckpt-all), requeue preempted tasks.
# Set to 1 for ckpt-all, 0 for a dedicated partition.
REQUEUE=1

# Cap how many array tasks run at once (SLURM array "%N" throttle).
# Empty = no cap (let the scheduler decide).
MAX_CONCURRENT=20

# -----------------------------------------------------------------------------
# SLEAP runtime (Apptainer image + model)
# -----------------------------------------------------------------------------
# Pinned SLEAP version baked into the .sif (see containers/sleap.def).
SLEAP_VERSION="1.6.3"

# Path to the built Apptainer image (see scripts/build_sleap_sif.sh).
SLEAP_SIF="${SLEAP_SIF:-$HOME/sleap_${SLEAP_VERSION}.sif}"

# Trained model(s). For a top-down model, list BOTH the centroid and the
# centered-instance model. For single-instance/bottom-up, list just one.
# Each entry may be a model directory, a best.ckpt, or a training_config.yaml.
MODEL_PATHS=(
  "/gscratch/CHANGE_ME/models/centroid"
  "/gscratch/CHANGE_ME/models/centered_instance"
)

# Inference device passed to sleap-nn (cuda, cuda:0, cpu, ...).
DEVICE="cuda"

# Inference subcommand. Default is the modern PyTorch CLI. The exact CLI has
# shifted across SLEAP 1.6.x -- override here if your pinned version differs
# (e.g. "sleap-track" for legacy-style invocation inside the container).
TRACK_SUBCMD="sleap-nn track"

# Extra args appended verbatim to the inference command. Put tracking and any
# tracker tuning here. Leave empty to disable tracking.
EXTRA_TRACK_ARGS="--tracking"

# -----------------------------------------------------------------------------
# Data layout -- where videos come from and where outputs go.
# -----------------------------------------------------------------------------
VIDEO_DIR="/gscratch/CHANGE_ME/videos"   # folder containing input videos
VIDEO_GLOB="*.mp4"                        # which files to treat as videos
OUTPUT_DIR="/gscratch/CHANGE_ME/predictions"  # one .slp written per video
LOG_DIR="${LOG_DIR:-$PWD/logs}"           # SLURM logs + manifests land here
