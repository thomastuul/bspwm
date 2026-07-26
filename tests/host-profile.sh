#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

load_profile() {
    # Variables are intentionally expanded by the nested shell.
    # shellcheck disable=SC2016
    env -i \
        HOME="$HOME" \
        PATH="$PATH" \
        BSPWM_CONFIG_DIR="$repository_root" \
        BSPWM_HOST_OVERRIDE="$1" \
        bash -c '
            source "$BSPWM_CONFIG_DIR/lib/host-profile.sh"
            printf "%s|%s|%s|%s\n" \
                "$BSPWM_HOST_NAME" "$BSPWM_HOST_ROLE" \
                "$BSPWM_TOP_PADDING" "$BSPWM_ENABLE_SLIVERBAR"
        '
}

[[ $(load_profile ikarus) == "Ikarus|laptop|25|1" ]]
[[ $(load_profile PEGASUS4) == "Pegasus4|desktop|25|1" ]]
[[ $(load_profile unknown-host) == "unknown-host|generic|25|1" ]]

BSPWM_CONFIG_DIR="$repository_root"
BSPWM_HOST_OVERRIDE=Ikarus
export BSPWM_CONFIG_DIR BSPWM_HOST_OVERRIDE
# The absolute test path is resolved at runtime inside and outside containers.
# shellcheck disable=SC1091
source "$repository_root/lib/host-profile.sh"
bspwm_feature_enabled BSPWM_ENABLE_SLIVERBAR
if env bash -c '[[ -v SLIVERBAR_CONFIG ]]'; then
    printf 'empty Sliverbar configuration was exported\n' >&2
    exit 1
fi
# The feature helper reads this value through indirect expansion.
# shellcheck disable=SC2034
BSPWM_ENABLE_SLIVERBAR=disabled
if bspwm_feature_enabled BSPWM_ENABLE_SLIVERBAR; then
    printf 'disabled feature evaluated as enabled\n' >&2
    exit 1
fi

child_result=$(
    export BSPWM_HOST_PROFILE_LOADED=1
    # Variables are intentionally expanded by the nested shell.
    # shellcheck disable=SC2016
    env BSPWM_HOST_OVERRIDE=Pegasus4 bash -c '
        unset BSPWM_HOST_PROFILE_LOADED
        source "$BSPWM_CONFIG_DIR/lib/host-profile.sh"
        bspwm_feature_enabled BSPWM_ENABLE_SLIVERBAR
        printf "%s|%s\n" "$BSPWM_HOST_NAME" "$BSPWM_HOST_ROLE"
    '
)
[[ $child_result == "Pegasus4|desktop" ]]

printf 'host profile tests passed\n'
