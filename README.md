# Hyak SLEAP parallel inference

Run [SLEAP](https://sleap.ai) pose-tracking inference on many videos in parallel on UW's
[**Hyak Klone**](https://hyak.uw.edu/docs/) cluster — **one SLURM job per video** — plus
from-scratch setup docs.

Targets the modern **PyTorch (`sleap-nn`)** SLEAP backend (v1.5+), run from a self-built,
version-pinned **Apptainer** container.

## Quickstart

Assuming you already have a Hyak account and your data is on the cluster:

```bash
git clone https://github.com/kylethieringer/cluster.git && cd cluster
# (auth/SSH-key setup: docs/01-getting-started.md §5)

# 1. Configure (account, partition, model paths, video/output dirs, ...)
$EDITOR config/inference.yaml

# 2. Build the SLEAP container image once
module load apptainer          # if needed
./scripts/build_sleap_sif.sh

# 3. Check what will run, then submit
./scripts/submit_inference.sh --dry-run
./scripts/submit_inference.sh

# 4. Watch it
squeue --me
```

New to Hyak? Start at [docs/01-getting-started.md](docs/01-getting-started.md).

## A second pipeline: motion correction (ANTsPy)

The same machinery also runs **imaging motion correction** with
[ANTsPy](https://github.com/ANTsX/ANTsPy) — **one CPU SLURM job per experiment**,
from its own container. It's independent of SLEAP (no GPU, separate image/config):

```bash
$EDITOR config/moco.config.sh   # account, CPU resources, data paths
./scripts/build_moco_sif.sh     # build the ANTsPy image once (clones the nre repo)
./scripts/submit_moco.sh --dry-run
./scripts/submit_moco.sh
```

See [docs/05-motion-correction.md](docs/05-motion-correction.md). It needs SSH
access to the private `oahmedlab/nifty-roi-extractor` repo (the `nre` package).

## Documentation

1. [Getting started](docs/01-getting-started.md) — account, login, login-vs-compute nodes,
   finding your account/partition.
2. [Storage & data](docs/02-storage-and-data.md) — `gscratch`, copying videos/models in.
3. [Building the SLEAP container](docs/03-sleap-apptainer.md) — backends, building the `.sif`,
   verifying GPU.
4. [Running inference](docs/04-running-inference.md) — configure, dry-run, submit, monitor,
   collect outputs.
5. [Motion correction (ANTsPy)](docs/05-motion-correction.md) — the CPU ANTsPy pipeline:
   build, configure, dry-run, submit.

## Layout

```
config/inference.yaml         # SLEAP: the one file you edit (allocation, model, data paths)
config/moco.config.sh         # motion correction: the one file you edit (CPU alloc, data paths)
containers/sleap.def          # Apptainer definition for the pinned SLEAP image
containers/moco.def           # Apptainer definition for the ANTsPy image (bakes in the nre package)
scripts/build_sleap_sif.sh    # build the SLEAP .sif from the definition
scripts/build_moco_sif.sh     # clone the nre repo + build the ANTsPy .sif
scripts/submit_inference.sh   # SLEAP: enumerate videos -> manifest -> submit the SLURM array
scripts/inference_array.slurm # SLEAP array job body: one task = one video
scripts/submit_moco.sh        # moco: enumerate experiments -> manifest -> submit the SLURM array
scripts/moco_array.slurm      # moco array job body: one task = one experiment
scripts/run_moco.py           # moco worker: motion-correct one experiment (uses nre)
docs/                         # setup + usage guides
```

## How it works

`submit_inference.sh` lists the videos across experiments (`RAW_DIR/<exptID>/*.mp4`), skips any
whose `.slp` output already exists, writes the rest to a manifest, and submits a SLURM **job
array** sized to that list. Each array task selects its video by `SLURM_ARRAY_TASK_ID` and runs
`apptainer exec --nv $SLEAP_SIF sleap-nn track ...`, writing one `.slp` per video into
`PROCESSED_DIR/<exptID>/`. Re-running resumes where it left off — useful on the preemptible
`ckpt-all` partition.

## Status / caveats

- Tested locally for script logic (manifest building, skip-existing, dry-run `sbatch`
  assembly). The container build and on-cluster GPU run must be validated on Hyak.
- SLEAP's install method and inference CLI shift across 1.6.x. The container's `pip install`
  line and the `TRACK_SUBCMD` / `EXTRA_TRACK_ARGS` config knobs are the two places to adjust if
  your pinned version differs.
