# 05 · Motion correction (ANTsPy)

A second, independent pipeline: **rigid+SyN motion correction of imaging volumes**
using [ANTsPy](https://github.com/ANTsX/ANTsPy), run **one SLURM job per
experiment** in parallel. It is the CPU sibling of the SLEAP pipeline and reuses
the same shape — a container, a single config file, and a job-array submitter.

This is **separate from the SLEAP image**: motion correction needs ANTsPy, not
SLEAP/PyTorch, and runs on **CPU** (ANTs SyN does not use a GPU).

## How it works

```
submit_moco.sh ──> finds experiments, skips done ones ──> writes a manifest
              └──> sbatch --array=1-N  moco_array.slurm  <manifest>

        SLURM array:  task 1 → experiment 1   task 2 → experiment 2   ... (parallel)
                      each: apptainer exec $MOCO_SIF  python3 run_moco.py ...
                      each writes  PROCESSED_DIR/<exptID>/{fixed,motion_corrected}.nii
```

Experiments are organized one folder deep: `RAW_DIR/<exptID>/*.nii`. For each
experiment the worker averages the first `FIXED_VOLUMES` volumes into a fixed/mean
brain (`fixed.nii`), then SyN-registers every volume to it
(`motion_corrected.nii`).

## The motion-correction code (`nre`)

The actual algorithm lives in the **private** Ahmed-lab repo
[`oahmedlab/nifty-roi-extractor`](https://github.com/oahmedlab/nifty-roi-extractor)
(the `nre` package: `io`, `moco`, `roi`). It isn't pip-installable as-is, so the
build script **clones it on the login node over SSH** at a pinned commit and bakes
the package into the image — no credentials ever enter the container build.

You therefore need **SSH access to that GitHub repo** from the node you build on:

```bash
ssh -T git@github.com          # should greet you by username
```

If that fails, set up an SSH key first (see
[docs/01-getting-started.md](01-getting-started.md) §5) and make sure your account
has access to `oahmedlab/nifty-roi-extractor`.

## 1. Build the container image

Set `ANTSPY_VERSION`, `MOCO_SIF`, and `NRE_COMMIT` in
[`config/moco.config.sh`](../config/moco.config.sh), then build **inside an
allocation, not on a login node** (a CPU node is fine — no GPU needed):

```bash
salloc -A psych -p ckpt-all -c 4 --mem 16G -t 04:00:00
module load apptainer        # if 'apptainer' isn't already on your PATH

./scripts/build_moco_sif.sh           # clones nre @ NRE_COMMIT, builds $MOCO_SIF
./scripts/build_moco_sif.sh --force   # rebuild even if the .sif exists
```

**Or submit it as a batch job** instead of holding an interactive allocation —
`sbatch` queues the build, runs it on a compute node, and writes the log to a
file you can check later. Submit from the repo root, and from a node whose SSH
key can reach the private `nre` repo (the clone happens on the compute node):

```bash
sbatch -A psych -p ckpt-all -c 4 --mem 16G -t 04:00:00 \
    -J build_moco -o build_moco-%j.out \
    --wrap 'module load apptainer; ./scripts/build_moco_sif.sh'

squeue --me                 # watch it queue/run
cat build_moco-<jobid>.out  # build output once it starts
```

The build clones the `nre` repo into `containers/.nre-src` (git-ignored, re-cloned
each build), pip-installs antspyx + numpy + scikit-learn + scipy, and copies the
package onto the image's `PYTHONPATH`. **Keep `MOCO_SIF` on `/gscratch`, not
`$HOME`** — the image plus build scratch are multi-GB and a home-quota path fails
partway through. To pull a newer version of the lab code, bump `NRE_COMMIT` and
rebuild with `--force`.

> **`exit status 137` / `Killed` during pip** = out of memory. Build inside an
> `salloc` (above), not a login node. If `/tmp` is RAM-backed, point the scratch
> dirs at disk: `export APPTAINER_TMPDIR=/gscratch/psych/$USER/apptainer_tmp`.

Verify the image:

```bash
apptainer exec "$MOCO_SIF" python3 -c "import ants; from nre import io, moco, roi; print(ants.__version__)"
```

## 2. Configure

Edit [`config/moco.config.sh`](../config/moco.config.sh) (or copy it to
`config/moco.config.local.sh`, which is git-ignored and takes precedence). Set at
minimum:

- `ACCOUNT`, `PARTITION`, `CPUS`, `MEM`, `TIME` — your allocation and per-job
  resources. **No GPU.** `MEM` should be generous (default `64G`): the worker
  holds the full functional volume plus a same-size output copy in RAM.
- `MOCO_SIF` — the image you just built.
- `DATA_ROOT`, `RAW_DIR`, `PROCESSED_DIR` — input/output locations. Volumes are
  read from `RAW_DIR/<exptID>/*.nii`; outputs go to `PROCESSED_DIR/<exptID>/`.
- `FIXED_VOLUMES`, `FUNC_GLOB`, `STRUC_GLOB` — fixed-brain averaging window and
  which `.nii` is the functional (vs. single-channel fallback) volume.

## 3. Dry run first

```bash
./scripts/submit_moco.sh --dry-run
```

Lists how many experiments were found / skipped / will be processed, writes the
manifest, and prints the exact `sbatch` command **without submitting**.

## 4. Submit

```bash
./scripts/submit_moco.sh
```

By default, experiments whose `PROCESSED_DIR/<exptID>/motion_corrected.nii`
already exists are **skipped** — re-running only processes what's left (handy
after preemption). Use `--force` to reprocess everything.

## 5. Monitor

```bash
squeue --me                 # your queued/running array tasks
sacct -j <jobid> --format=JobID,State,Elapsed,MaxRSS,ReqTRES%40
```

Per-task logs are in `logs/`:
- `logs/moco-<jobid>_<taskid>.out` — stdout (the command run, progress).
- `logs/moco-<jobid>_<taskid>.err` — stderr / errors.

## Tuning notes

- **Preemption (`ckpt-all`):** motion correction is **not checkpointed** — a
  preempted task restarts the experiment from scratch. The skip-existing logic
  means finished experiments aren't redone, but a long single experiment that
  keeps getting preempted may never finish. For long runs prefer a **dedicated CPU
  partition** (set `PARTITION` and `REQUEUE=0`).
- **Memory:** if tasks are killed with `OUT_OF_MEMORY` (visible in `sacct`), raise
  `MEM`. Peak ≈ 2× the functional volume size.
- **Walltime:** `TIME` is *per experiment*; SyN over many volumes is slow. Tasks
  hitting the limit show as `TIMEOUT`.
- **Threads:** the array script pins ANTs/ITK to `CPUS`. More cores speed up each
  SyN registration but reduce how many experiments run concurrently.
