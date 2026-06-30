#!/usr/bin/env python3
"""Translate a YAML config into bash variable assignments.

Read by scripts/_common.sh's load_config: it runs

    eval "$(python3 scripts/config_to_env.py config/inference.yaml)"

so the rest of the pipeline keeps consuming the same plain bash variables it
always has (ACCOUNT, MODEL_PATHS, DEVICE, ...). The point is that humans edit a
simple, commented YAML file instead of bash -- lists instead of array syntax, no
quoting gymnastics, and clear error messages when something is wrong.

The translation has two layers:
  * a GENERIC core (parse YAML -> emit KEY=value / KEY=(items)) that is not
    specific to inference and can be reused by other configs (e.g. moco), and
  * an inference-specific defaults/validation step applied on top.

On any problem we print "config error: ..." to stderr and exit non-zero, so a
bad config aborts the submit instead of producing a half-broken bash env.
"""

import os
import shlex
import sys


def die(msg):
    """Print a friendly error and exit non-zero so load_config aborts."""
    sys.stderr.write(f"config error: {msg}\n")
    sys.exit(1)


# --- YAML parsing -----------------------------------------------------------
# Prefer PyYAML when it's importable. Fall back to a tiny parser for the
# documented subset (flat "key: value", "- item" lists, "#" comments) so the
# helper still works on a login node that happens to lack PyYAML.

def parse_yaml(text, path):
    try:
        import yaml
    except ImportError:
        return _parse_yaml_subset(text, path)
    try:
        data = yaml.safe_load(text)
    except yaml.YAMLError as e:
        die(f"could not parse {path}: {e}")
    if data is None:
        data = {}
    if not isinstance(data, dict):
        die(f"{path}: top level must be a mapping of key: value")
    return data


def _strip_comment(s):
    """Drop a trailing ' #...' comment that isn't inside quotes."""
    out = []
    quote = None
    for i, ch in enumerate(s):
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
        elif ch in ("'", '"'):
            quote = ch
            out.append(ch)
        elif ch == "#" and (i == 0 or s[i - 1] in " \t"):
            break
        else:
            out.append(ch)
    return "".join(out).rstrip()


def _scalar(raw, path, lineno):
    s = raw.strip()
    if not s:
        return ""
    if (s[0] == s[-1]) and s[0] in ("'", '"') and len(s) >= 2:
        return s[1:-1]
    low = s.lower()
    if low in ("true", "yes"):
        return True
    if low in ("false", "no"):
        return False
    if low in ("null", "~", "none"):
        return None
    if _is_int(s):
        return int(s)
    return s


def _is_int(s):
    try:
        int(s)
        return True
    except ValueError:
        return False


def _parse_yaml_subset(text, path):
    """Minimal parser: flat scalars and one-level lists. Not full YAML."""
    data = {}
    got_items = set()          # keys that actually received "- " list items
    current_list_key = None
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = _strip_comment(raw)
        if not line.strip():
            continue
        stripped = line.lstrip()
        # list item belonging to the most recent "key:" with no inline value
        if stripped.startswith("- "):
            if current_list_key is None:
                die(f"{path}:{lineno}: list item without a key")
            data[current_list_key].append(_scalar(stripped[2:], path, lineno))
            got_items.add(current_list_key)
            continue
        if line[:1] in (" ", "\t"):
            die(f"{path}:{lineno}: unexpected indentation (subset parser "
                f"supports only flat keys and '- ' lists)")
        if ":" not in line:
            die(f"{path}:{lineno}: expected 'key: value'")
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()
        if not key:
            die(f"{path}:{lineno}: empty key")
        if value == "":
            data[key] = []          # may become a list via following "- " lines
            current_list_key = key
        else:
            data[key] = _scalar(value, path, lineno)
            current_list_key = None
    # A key that opened with an empty value but received no "- " items is a null
    # scalar (matches PyYAML), not an empty list.
    for key in list(data):
        if data[key] == [] and key not in got_items:
            data[key] = None
    return data


# --- generic emission -------------------------------------------------------

def emit(name, value):
    """Return one bash assignment line for a scalar/bool/list value."""
    if isinstance(value, list):
        items = " ".join(shlex.quote(_render_scalar(v)) for v in value)
        return f"{name}=({items})"
    return f"{name}={shlex.quote(_render_scalar(value))}"


def _render_scalar(value):
    if isinstance(value, bool):
        return "1" if value else "0"
    if value is None:
        return ""
    return str(value)


# --- inference-specific defaults & validation -------------------------------
# YAML key -> bash variable name. Most are a straight uppercase; "models" is the
# one rename (-> MODEL_PATHS, the array the pipeline expects).
KEY_TO_VAR = {
    "account": "ACCOUNT",
    "user": "USER_ID",
    "partition": "PARTITION",
    "gpu_spec": "GPU_SPEC",
    "cpus": "CPUS",
    "mem": "MEM",
    "time": "TIME",
    "requeue": "REQUEUE",
    "max_concurrent": "MAX_CONCURRENT",
    "sleap_version": "SLEAP_VERSION",
    "sleap_sif": "SLEAP_SIF",
    "models": "MODEL_PATHS",
    "device": "DEVICE",
    "track_subcmd": "TRACK_SUBCMD",
    "extra_track_args": "EXTRA_TRACK_ARGS",
    "data_root": "DATA_ROOT",
    "raw_dir": "RAW_DIR",
    "video_glob": "VIDEO_GLOB",
    "processed_dir": "PROCESSED_DIR",
    "log_dir": "LOG_DIR",
}

REQUIRED = ("account", "partition", "models")
DEFAULTS = {
    "gpu_spec": "--gpus=1",
    "cpus": 8,
    "mem": "32G",
    "time": "04:00:00",
    "requeue": True,
    "sleap_version": "1.6.3",
    "device": "cuda",
    "track_subcmd": "sleap-nn track",
    "extra_track_args": "--tracking",
    "video_glob": "*.mp4",
}


def build_inference_env(data, path):
    unknown = set(data) - set(KEY_TO_VAR)
    if unknown:
        die(f"{path}: unknown key(s): {', '.join(sorted(unknown))}")

    cfg = dict(DEFAULTS)
    cfg.update({k: v for k, v in data.items() if v is not None})

    for key in REQUIRED:
        if key not in cfg or cfg[key] in ("", [], None):
            die(f"{path}: '{key}' is required")

    if cfg["account"] == "CHANGE_ME":
        die(f"{path}: set 'account' to your allocation (see 'groups')")

    models = cfg["models"]
    if not isinstance(models, list):
        die(f"{path}: 'models' must be a list (one '- path' per model)")
    if not models:
        die(f"{path}: 'models' must list at least one model path")

    for int_key in ("cpus", "max_concurrent"):
        if int_key in cfg and cfg[int_key] is not None:
            if not isinstance(cfg[int_key], int) or isinstance(cfg[int_key], bool):
                die(f"{path}: '{int_key}' must be an integer")
    if not isinstance(cfg["requeue"], bool):
        die(f"{path}: 'requeue' must be true or false")

    # The username embedded in default /gscratch paths. Falls back to the
    # cluster login ($USER) so a fresh clone "just works" without editing paths;
    # set 'user:' in the config to override (e.g. a shared lab directory).
    def need_user(what):
        u = cfg.get("user") or os.environ.get("USER")
        if not u:
            die(f"{path}: cannot determine 'user' for {what}: set 'user:' in "
                f"the config (or ensure $USER is set on the cluster)")
        return u

    # Derived defaults, built from account + user so nothing is hardcoded.
    if cfg.get("data_root") in (None, ""):
        cfg["data_root"] = f"/gscratch/scrubbed/{need_user('data_root')}/data"
    data_root = str(cfg["data_root"])
    cfg.setdefault("raw_dir", f"{data_root}/raw")
    cfg.setdefault("processed_dir", f"{data_root}/processed")
    cfg.setdefault(
        "sleap_sif",
        f"/gscratch/{cfg['account']}/{need_user('sleap_sif')}"
        f"/sleap_{cfg['sleap_version']}.sif",
    )
    # LOG_DIR defaults to $PWD/logs; leave it to the bash side so it resolves at
    # submit time. Only emit it if the user set it explicitly.

    lines = []
    for key, var in KEY_TO_VAR.items():
        if key in cfg and cfg[key] is not None:
            lines.append(emit(var, cfg[key]))
    return "\n".join(lines)


def main(argv):
    if len(argv) != 2:
        die("usage: config_to_env.py <config.yaml>")
    path = argv[1]
    try:
        with open(path) as f:
            text = f.read()
    except OSError as e:
        die(f"could not read {path}: {e}")
    data = parse_yaml(text, path)
    sys.stdout.write(build_inference_env(data, path) + "\n")


if __name__ == "__main__":
    main(sys.argv)
