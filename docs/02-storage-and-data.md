# 02 · Storage and moving your data

You need three things on the cluster before running inference: your **videos**, your **trained
SLEAP model(s)**, and a place for **outputs**. Official storage docs:
<https://hyak.uw.edu/docs/storage/gscratch>.

## Where to put things

| What | Where | Notes |
|------|-------|-------|
| Videos | `/gscratch/<group>/.../videos` | Large, fast scratch storage. |
| Model(s) | `/gscratch/<group>/.../models` | One dir per model (centroid, centered_instance, …). |
| Outputs (`.slp`) | `/gscratch/<group>/.../predictions` | One `.slp` per video. |
| This repo | `/gscratch/<group>/<you>` | Clone here (not home). See [01 · §5](01-getting-started.md#5-get-this-repo-onto-the-cluster). |

**`gscratch`** is the high-performance shared filesystem for active work. It is **not backed
up** and may have purge policies — keep originals elsewhere and archive results you care about
(see *Lolo* / *Kopah* below). Check your quota with `hyakalloc` or `gscratch-usage`.

> Your home directory (`~`) is small. Don't put videos or `.sif` images there if you can use
> `gscratch`.

## Getting videos onto the cluster

Run these **from your local machine** (not from a login node).

**rsync (recommended — resumable):**
```bash
rsync -avh --progress /local/path/videos/ \
    <UWNetID>@klone.hyak.uw.edu:/gscratch/<group>/<you>/videos/
```

**scp (simple):**
```bash
scp /local/path/*.mp4 <UWNetID>@klone.hyak.uw.edu:/gscratch/<group>/<you>/videos/
```

**Globus (best for large/many files):** set up a Globus endpoint and transfer in the web UI —
robust to interruptions. Docs: <https://hyak.uw.edu/docs/storage/globus>.

**Kopah S3 (object storage):** if your data lives in Kopah, pull it on the cluster with the S3
CLI. Docs: <https://hyak.uw.edu/docs/storage/kopah>.

## Long-term archive

For results/raw data you want to keep, use **Lolo** (tape archive) or **Kopah** rather than
leaving them on `gscratch`. Archive docs: <https://hyak.uw.edu/docs/storage/lolo>.

## Next

→ [03-sleap-apptainer.md](03-sleap-apptainer.md): build the SLEAP container image you'll run
inference with.
