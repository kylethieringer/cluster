#!/usr/bin/env python3
"""Motion-correct one experiment with ANTsPy (the Ahmed-lab `nre` package).

Single-experiment worker invoked by scripts/moco_array.slurm inside the moco
Apptainer image (which puts `nre` on PYTHONPATH). One SLURM array task == one
experiment. For the given experiment it:

  1. finds the functional .nii (prefers --func-glob, falls back to --struc-glob),
  2. builds a mean/fixed brain from the first --fixed-volumes volumes,
  3. writes <out>/fixed.nii,
  4. runs SyN motion correction over every volume,
  5. writes <out>/motion_corrected.nii.

Idempotent: if <out>/motion_corrected.nii already exists it exits without work.

Adapted for one experiment (config-driven cluster paths) from the lab's
motion_correct_raw_data.py serial driver.
"""
import argparse
import gc
import glob
import os
import sys

import ants
import numpy as np

from nre import io, moco


def find_functional(raw_dir: str, func_glob: str, struc_glob: str) -> str:
    """Return the .nii to motion-correct: the functional channel if present,
    otherwise the structural channel (single-channel recordings)."""
    for pattern in (func_glob, struc_glob):
        matches = sorted(glob.glob(os.path.join(raw_dir, pattern)))
        if matches:
            return matches[0]
    raise FileNotFoundError(
        f"no .nii matching {func_glob!r} or {struc_glob!r} in {raw_dir}"
    )


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--raw", required=True,
                   help="experiment's raw folder (RAW_DIR/<exptID>) holding the .nii(s)")
    p.add_argument("--out", required=True,
                   help="experiment's output folder (PROCESSED_DIR/<exptID>)")
    p.add_argument("--fixed-volumes", type=int, default=300,
                   help="leading volumes averaged into the fixed/mean brain (default: 300)")
    p.add_argument("--func-glob", default="*channel_2.nii",
                   help="glob for the functional channel (default: *channel_2.nii)")
    p.add_argument("--struc-glob", default="*channel_1.nii",
                   help="fallback glob when only one channel was recorded (default: *channel_1.nii)")
    p.add_argument("--force", action="store_true",
                   help="re-run even if motion_corrected.nii already exists")
    args = p.parse_args()

    out_nii = os.path.join(args.out, "motion_corrected.nii")
    if os.path.exists(out_nii) and not args.force:
        print(f"output already exists, skipping: {out_nii}")
        return 0

    os.makedirs(args.out, exist_ok=True)

    func_channel = find_functional(args.raw, args.func_glob, args.struc_glob)
    print(f"functional channel: {func_channel}")

    # io.load returns a numpy array (ants.image_read(...).numpy()). A functional
    # recording is 4D with time as the LAST axis (x, y, z, t) -- ANTs preserves
    # the NIfTI dim order. Treat a 3D volume as a single timepoint.
    data = io.load(func_channel)
    if data.ndim == 3:
        data = data[..., np.newaxis]
    if data.ndim != 4:
        raise ValueError(f"expected a 3D or 4D volume, got shape {data.shape}")
    n_vols = data.shape[-1]
    print(f"loaded {func_channel}: shape {data.shape} ({n_vols} volumes)")

    # Build the fixed/mean brain by averaging the leading volumes over the time
    # axis. nre.moco no longer provides this (it only exposes apply()), so do it
    # here. Clamp the window to the number of volumes actually present.
    n_fixed = min(args.fixed_volumes, n_vols)
    fixed_np = data[..., :n_fixed].mean(axis=-1)
    print(f"built fixed brain from first {n_fixed} volume(s)")

    fixed_nii = os.path.join(args.out, "fixed.nii")
    io.save(fixed_nii, fixed_np)
    print(f"wrote {fixed_nii}")

    # Motion-correct every volume against the fixed brain. nre.moco.apply wraps
    # ants.registration (SyN), so it works on ANTs images, not numpy: convert
    # each volume in, take the warped result back out as numpy. The output is a
    # full second copy of the stack -- this is the memory peak the docs warn of.
    fixed_img = ants.from_numpy(fixed_np)
    corrected = np.empty_like(data)
    print(f"running motion correction (SyN, per volume) over {n_vols} volumes")
    for t in range(n_vols):
        moving_img = ants.from_numpy(data[..., t])
        corrected[..., t] = moco.apply(fixed_img, moving_img).numpy()
        if (t + 1) % 50 == 0 or t + 1 == n_vols:
            print(f"  motion-corrected {t + 1}/{n_vols} volumes", flush=True)

    del data
    gc.collect()

    io.save(out_nii, corrected)
    print(f"wrote {out_nii}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
