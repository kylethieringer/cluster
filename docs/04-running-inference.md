# 04 · Running parallel inference

This runs SLEAP inference on every video across your experiments, **one SLURM job per video**,
in parallel. Videos are organized one experiment per folder: `RAW_DIR/<exptID>/<video>.mp4`.

## How it works

```
submit_inference.sh ──> finds videos, skips done ones ──> writes a manifest
                   └──> sbatch --array=1-N  inference_array.slurm  <manifest>

           SLURM array:  task 1 → video 1     task 2 → video 2     ... (run in parallel)
                         each: apptainer exec --nv $SLEAP_SIF  sleap-nn track ...
                         each writes  PROCESSED_DIR/<exptID>/<video>.predictions.slp
```

Each array task picks its video by `SLURM_ARRAY_TASK_ID` and runs the inference command from
your config. Tasks are independent, so they run as fast as the scheduler grants GPUs.

## 1. Configure

Edit [`config/inference.yaml`](../config/inference.yaml) (or copy it to
`config/inference.local.yaml`, which is git-ignored and takes precedence). Set at minimum:

- `account`, `partition`, `gpu_spec`, `mem`, `time` — your allocation and per-job resources.
- `models` — your trained model(s). Top-down = centroid **and** centered-instance; single-
  instance/bottom-up = one entry.
- `sleap_sif` — optional. Defaults to `/gscratch/<account>/<user>/sleap_<version>.sif`
  (the image from [03-sleap-apptainer.md](03-sleap-apptainer.md)); set only to override.
- `data_root`, `raw_dir`, `video_glob`, `processed_dir` — input/output locations. `data_root`
  defaults to `/gscratch/scrubbed/<user>/data`. Videos are read from `raw_dir/<exptID>/*.mp4`;
  outputs are written to `processed_dir/<exptID>/`.

`<user>` defaults to your cluster login (`$USER`), so on your own allocation the paths above
work untouched. Set `user:` in the config only to point at a different or shared name.
- `extra_track_args` — keep `--tracking` to track across frames; clear it for per-frame only.

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

It prints the submitted job ID. By default, videos whose
`PROCESSED_DIR/<exptID>/<name>.predictions.slp` already exists are **skipped** — so re-running
only processes what's left (handy after
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

Results are one `.slp` per video under `PROCESSED_DIR/<exptID>/`. Open them in the SLEAP GUI, or copy them back
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
