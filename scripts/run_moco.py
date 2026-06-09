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

    # Build the fixed/mean brain. The structural reference is the functional
    # channel itself (matches the lab driver). Load, average, free before the
    # full motion-correction load to keep the memory peak down.
    print(f"loading volume for fixed brain (first {args.fixed_volumes} volumes)")
    struc_data = io.load(func_channel)
    mean_brain, fixed_brain = moco.generate_fixed(struc_data, args.fixed_volumes)
    del struc_data
    gc.collect()

    fixed_nii = os.path.join(args.out, "fixed.nii")
    io.save(fixed_nii, mean_brain)
    print(f"wrote {fixed_nii}")

    # Motion-correct every volume against the fixed brain.
    print("loading functional volume for motion correction")
    func_data = io.load(func_channel)
    print("running motion correction (SyN, per volume)")
    moco_func_brain = moco.motion_correction(func_data, fixed_brain)
    del func_data
    gc.collect()

    io.save(out_nii, moco_func_brain)
    print(f"wrote {out_nii}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
