# 03 · Building the SLEAP container

Inference runs inside an **Apptainer** (formerly Singularity) container so the exact SLEAP
version, CUDA, and PyTorch are pinned and reproducible — no fragile per-user conda/CUDA setup.

## Know your model's backend (important)

SLEAP changed deep-learning backends:

- **SLEAP ≤ 1.4.1** used **TensorFlow**.
- **SLEAP ≥ 1.5** uses **PyTorch** (the `sleap-nn` engine). Current release is **1.6.x**.

**A model only runs on the backend it was trained with.** This repo targets the **modern
PyTorch (`sleap-nn`)** backend. If your model was trained with legacy TensorFlow SLEAP, you
must either retrain/convert it or build a legacy container instead (out of scope here).

To check, look at the SLEAP version you trained in, or inspect the model directory: PyTorch
models contain `best.ckpt` / `training_config.yaml`; legacy TF models have a
`training_config.json` and TensorFlow checkpoint files.

> There is **no official prebuilt SLEAP container** for the PyTorch backend, so we build our
> own from [`containers/sleap.def`](../containers/sleap.def). (The community
> `maouw/sleap-container` repo is legacy/TensorFlow and last updated in 2024 — not used here.)

## Build the image

Set `SLEAP_VERSION` and `SLEAP_SIF` in [`config/inference.config.sh`](../config/inference.config.sh),
then on the cluster. **Build inside an allocation with ample RAM, not on a login node** — the
torch + CUDA wheel set is large and a login node's memory cap will get the build OOM-killed:

```bash
# Grab a CPU compute node with plenty of memory (no GPU needed to build):
salloc -A psych -p ckpt-all -c 4 --mem 48G -t 02:00:00

# apptainer may need to be loaded first:
module load apptainer   # if 'apptainer' isn't already on your PATH

./scripts/build_sleap_sif.sh           # builds $SLEAP_SIF from containers/sleap.def
./scripts/build_sleap_sif.sh --force   # rebuild even if the .sif exists
```

The build downloads a CUDA base image and pip-installs the pinned SLEAP — it can take a while
and a few GB. The script points Apptainer's scratch (`APPTAINER_TMPDIR`/`APPTAINER_CACHEDIR`)
at disk next to your `.sif` so wheel extraction doesn't fill a RAM-backed `/tmp`; override those
env vars before running if you want a different location (e.g. `/gscratch/psych`).

**Keep `SLEAP_SIF` on scratch, not `$HOME`.** The image is several GB and the build scratch dir
sits next to it, so a home-quota path will fail with "Disk quota exceeded" partway through. Set it
once in [`config/inference.config.sh`](../config/inference.config.sh) to a `/gscratch` path, e.g.:

```bash
SLEAP_SIF="${SLEAP_SIF:-/gscratch/psych/<you>/sleap_${SLEAP_VERSION}.sif}"
```

That single setting also relocates the build scratch (`<sif-dir>/.apptainer-build/...`), so you
don't need to set `APPTAINER_TMPDIR` separately. Make sure that scratch dir exists and has room
(the image plus transient build scratch peak around ~15–20 GB combined).

> **`FATAL: ... exit status 137` / `Killed` during the pip step** means the build ran out of
> memory (137 = killed by SIGKILL). It almost always means you built on a login node or with too
> little `--mem`. Rerun inside an `salloc` with `--mem 48G` (above). If it still dies, your `/tmp`
> may be RAM-backed — point the scratch dirs at real disk:
> `export APPTAINER_TMPDIR=/gscratch/psych/$USER/apptainer_tmp` before building.

> If the build fails on the install step, the pinned version's install instructions may differ.
> Check <https://docs.sleap.ai/> and <https://nn.sleap.ai/> and adjust the `pip install` line
> (and the CUDA base tag) in `containers/sleap.def`.

## Verify GPU access

The `--nv` flag is what exposes the host GPU/NVIDIA driver to the container. Always use it.
Test inside a short GPU allocation:

```bash
salloc -A <account> -p <gpu-partition> --gpus=1 -c 2 --mem 8G -t 00:20:00

apptainer exec --nv "$SLEAP_SIF" python3 -c "import torch; print(torch.version.cuda, torch.cuda.is_available())"
# -> 13.0  True     (CUDA build should match the sleap.def base image, currently 13.x)
apptainer exec --nv "$SLEAP_SIF" nvidia-smi
# -> shows the allocated GPU
```

If `torch.version.cuda` doesn't match the major version of the `From:` base tag in
[`containers/sleap.def`](../containers/sleap.def), SLEAP changed the torch CUDA build it pulls —
bump the base tag and the pip `--extra-index-url` (cu1XX) in the def together and rebuild.

If `torch.cuda.is_available()` prints `False`, you either forgot `--nv`, aren't in a GPU
allocation, or the container's CUDA doesn't match the driver — recheck the partition/`--gpus`
request and the base image tag in `sleap.def`.

## Next

→ [04-running-inference.md](04-running-inference.md): configure and submit the parallel
inference jobs.
