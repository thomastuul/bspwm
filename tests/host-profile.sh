#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

load_profile() {
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
# shellcheck source=../lib/host-profile.sh
source "$repository_root/lib/host-profile.sh"
bspwm_feature_enabled BSPWM_ENABLE_SLIVERBAR
BSPWM_ENABLE_SLIVERBAR=disabled
! bspwm_feature_enabled BSPWM_ENABLE_SLIVERBAR

child_result=$(
    export BSPWM_HOST_PROFILE_LOADED=1
    env BSPWM_HOST_OVERRIDE=Pegasus4 bash -c '
        unset BSPWM_HOST_PROFILE_LOADED
        source "$BSPWM_CONFIG_DIR/lib/host-profile.sh"
        bspwm_feature_enabled BSPWM_ENABLE_SLIVERBAR
        printf "%s|%s\n" "$BSPWM_HOST_NAME" "$BSPWM_HOST_ROLE"
    '
)
[[ $child_result == "Pegasus4|desktop" ]]

printf 'host profile tests passed\n'
