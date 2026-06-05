# 04 · Running parallel inference

This runs SLEAP inference on every video in a folder, **one SLURM job per video**, in parallel.

## How it works

```
submit_inference.sh ──> finds videos, skips done ones ──> writes a manifest
                   └──> sbatch --array=1-N  inference_array.slurm  <manifest>

           SLURM array:  task 1 → video 1     task 2 → video 2     ... (run in parallel)
                         each: apptainer exec --nv $SLEAP_SIF  sleap-nn track ...
                         each writes  OUTPUT_DIR/<video>.predictions.slp
```

Each array task picks its video by `SLURM_ARRAY_TASK_ID` and runs the inference command from
your config. Tasks are independent, so they run as fast as the scheduler grants GPUs.

## 1. Configure

Edit [`config/inference.config.sh`](../config/inference.config.sh) (or copy it to
`config/inference.config.local.sh`, which is git-ignored and takes precedence). Set at minimum:

- `ACCOUNT`, `PARTITION`, `GPU_SPEC`, `MEM`, `TIME` — your allocation and per-job resources.
- `SLEAP_SIF` — the image from [03-sleap-apptainer.md](03-sleap-apptainer.md).
- `MODEL_PATHS` — your trained model(s). Top-down = centroid **and** centered-instance; single-
  instance/bottom-up = one entry.
- `VIDEO_DIR`, `VIDEO_GLOB`, `OUTPUT_DIR` — input/output locations.
- `EXTRA_TRACK_ARGS` — keep `--tracking` to track across frames; clear it for per-frame only.

## 2. Dry run first

```bash
./scripts/submit_inference.sh --dry-run
```

This lists how many videos were found / skipped / will be processed, writes the manifest, and
prints the exact `sbatch` command **without submitting**. Confirm the counts and command look
right.

## 3. Submit

```bash
./scripts/submit_inference.sh
```

It prints the submitted job ID. By default, videos whose `OUTPUT_DIR/<name>.predictions.slp`
already exists are **skipped** — so re-running only processes what's left (handy after
preemption on `ckpt-all`). Use `--force` to reprocess everything.

## 4. Monitor

```bash
squeue --me                 # your queued/running array tasks
sacct -j <jobid>            # per-task state (COMPLETED / FAILED / ...)
sacct -j <jobid> --format=JobID,State,Elapsed,MaxRSS,ReqTRES%40
```

Per-task logs are in `logs/`:
- `logs/sleap-<jobid>_<taskid>.out` — stdout, including `nvidia-smi` and the command run.
- `logs/sleap-<jobid>_<taskid>.err` — stderr / errors.

## 5. Collect outputs

Results are one `.slp` per video in `OUTPUT_DIR`. Open them in the SLEAP GUI, or copy them back
to your machine (see [02-storage-and-data.md](02-storage-and-data.md)).

## Tuning notes

- **`ckpt-all` (free, preemptible):** set `REQUEUE=1` (default). Preempted tasks requeue and
  resume from scratch; the skip-existing logic means you don't redo finished videos.
- **Throughput:** `MAX_CONCURRENT` caps simultaneous tasks (be a good cluster citizen / respect
  GPU limits). Empty = let SLURM decide.
- **Walltime:** `TIME` is *per video*. Long videos need more; if tasks hit the limit they'll be
  killed (visible as `TIMEOUT` in `sacct`).
- **CLI drift:** if your pinned SLEAP version's CLI differs, change `TRACK_SUBCMD` /
  `EXTRA_TRACK_ARGS` in the config — the job script passes them through verbatim.
