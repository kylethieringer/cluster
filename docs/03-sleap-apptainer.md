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
then on the cluster:

```bash
# apptainer may need to be loaded first:
module load apptainer   # if 'apptainer' isn't already on your PATH

./scripts/build_sleap_sif.sh           # builds $SLEAP_SIF from containers/sleap.def
./scripts/build_sleap_sif.sh --force   # rebuild even if the .sif exists
```

The build downloads a CUDA base image and pip-installs the pinned SLEAP — it can take a while
and a few GB. Run it on a compute node (`salloc`) rather than a login node if it's heavy.

> If the build fails on the install step, the pinned version's install instructions may differ.
> Check <https://docs.sleap.ai/> and <https://nn.sleap.ai/> and adjust the `pip install` line
> (and the CUDA base tag) in `containers/sleap.def`.

## Verify GPU access

The `--nv` flag is what exposes the host GPU/NVIDIA driver to the container. Always use it.
Test inside a short GPU allocation:

```bash
salloc -A <account> -p <gpu-partition> --gpus=1 -c 2 --mem 8G -t 00:20:00

apptainer exec --nv "$SLEAP_SIF" python3 -c "import torch; print(torch.cuda.is_available())"
# -> True
apptainer exec --nv "$SLEAP_SIF" nvidia-smi
# -> shows the allocated GPU
```

If `torch.cuda.is_available()` prints `False`, you either forgot `--nv`, aren't in a GPU
allocation, or the container's CUDA doesn't match the driver — recheck the partition/`--gpus`
request and the base image tag in `sleap.def`.

## Next

→ [04-running-inference.md](04-running-inference.md): configure and submit the parallel
inference jobs.
