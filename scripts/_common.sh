# shellcheck shell=bash
# Shared helpers sourced by the other scripts. Not meant to be run directly.

# Absolute path to the repo root (parent of this scripts/ dir).
repo_root() {
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

# Load the YAML config. Prefers a git-ignored *.local.yaml override, then the
# tracked default. Honors $CONFIG_FILE if the caller set it.
#
# The YAML is translated to plain bash variable assignments by config_to_env.py
# (which also validates it and reports friendly errors), and those assignments
# are eval'd here. Everything downstream just reads the resulting variables
# (ACCOUNT, MODEL_PATHS, DEVICE, ...).
# Usage: load_config "$CONFIG_FILE_OR_EMPTY"
load_config() {
    local explicit="${1:-${CONFIG_FILE:-}}"
    local root cfg env_text
    root="$(repo_root)"

    if [[ -n "$explicit" ]]; then
        cfg="$explicit"
    elif [[ -f "$root/config/inference.local.yaml" ]]; then
        cfg="$root/config/inference.local.yaml"
    else
        cfg="$root/config/inference.yaml"
    fi

    if [[ ! -f "$cfg" ]]; then
        echo "ERROR: config file not found: $cfg" >&2
        return 1
    fi

    # YAML configs (SLEAP) are translated + validated by config_to_env.py; on
    # error it prints "config error: ..." to stderr and exits non-zero, so abort
    # rather than eval a partial env. Bash configs (moco) are still plain shell
    # and are sourced directly.
    case "$cfg" in
        *.yaml|*.yml)
            if ! env_text="$(python3 "$root/scripts/config_to_env.py" "$cfg")"; then
                return 1
            fi
            eval "$env_text"
            ;;
        *)
            # shellcheck source=/dev/null
            source "$cfg"
            ;;
    esac
    CONFIG_FILE="$cfg"
    export CONFIG_FILE
}

# Print to stderr and exit non-zero.
die() {
    echo "ERROR: $*" >&2
    exit 1
}

# Map a raw video path to its output .slp path. Videos live one folder deep
# (RAW_DIR/<exptID>/<name>.mp4); the experiment subfolder is mirrored under
# PROCESSED_DIR, so the output is PROCESSED_DIR/<exptID>/<name>.predictions.slp.
# Requires PROCESSED_DIR to be set (sourced from the config).
out_path_for() {
    local video="$1" exptid base
    exptid="$(basename "$(dirname "$video")")"
    base="$(basename "$video")"
    printf '%s/%s/%s.predictions.slp' "$PROCESSED_DIR" "$exptid" "${base%.*}"
}
