# shellcheck shell=bash
# Shared helpers sourced by the other scripts. Not meant to be run directly.

# Absolute path to the repo root (parent of this scripts/ dir).
repo_root() {
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

# Source the config file. Prefers a git-ignored *.local.sh override, then the
# tracked default. Honors $CONFIG_FILE if the caller set it.
# Usage: load_config "$CONFIG_FILE_OR_EMPTY"
load_config() {
    local explicit="${1:-${CONFIG_FILE:-}}"
    local root cfg
    root="$(repo_root)"

    if [[ -n "$explicit" ]]; then
        cfg="$explicit"
    elif [[ -f "$root/config/inference.config.local.sh" ]]; then
        cfg="$root/config/inference.config.local.sh"
    else
        cfg="$root/config/inference.config.sh"
    fi

    if [[ ! -f "$cfg" ]]; then
        echo "ERROR: config file not found: $cfg" >&2
        return 1
    fi
    # shellcheck source=/dev/null
    source "$cfg"
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
