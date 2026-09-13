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

[[ $(load_profile ikarus2) == "Ikarus2|laptop|25|1" ]]
[[ $(load_profile Ikarus2) == "Ikarus2|laptop|25|1" ]]
[[ $(load_profile PEGASUS4) == "Pegasus4|desktop|25|1" ]]
[[ $(load_profile unknown-host) == "unknown-host|generic|25|1" ]]

BSPWM_CONFIG_DIR="$repository_root"
BSPWM_HOST_OVERRIDE=Ikarus2
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

# Isolated profile files exercise priority without changing the checkout.
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/hosts/Ikarus2" "$fixture/hosts/Pegasus4" "$fixture/hosts/unknown-host"
cp -r "$repository_root/lib" "$fixture/"
printf 'SLIVERBAR_CONFIG=/profile.conf\n' >"$fixture/hosts/Ikarus2/profile.sh"
printf 'BSPWM_TOP_PADDING=999\n' >"$fixture/hosts/unknown-host/profile.sh"
touch "$fixture/hosts/Ikarus2/sliverbar.conf" "$fixture/hosts/Pegasus4/sliverbar.conf"
# shellcheck disable=SC2016
env -i HOME="$HOME" PATH="$PATH" BSPWM_CONFIG_DIR="$fixture" bash -eu -c '
    BSPWM_HOST_OVERRIDE=Ikarus2
    SLIVERBAR_CONFIG=/environment.conf
    source "$BSPWM_CONFIG_DIR/lib/host-profile.sh"
    [[ $SLIVERBAR_CONFIG == /profile.conf ]]
    [[ $(BSPWM_HOST_OVERRIDE=Pegasus4 bash -c '"'"'source "$BSPWM_CONFIG_DIR/lib/host-profile.sh"; printf "%s" "$SLIVERBAR_CONFIG"'"'"') == "$BSPWM_CONFIG_DIR/hosts/Pegasus4/sliverbar.conf" ]]
    unset BSPWM_HOST_PROFILE_LOADED
    BSPWM_HOST_OVERRIDE=unknown-host
    source "$BSPWM_CONFIG_DIR/lib/host-profile.sh"
    [[ $BSPWM_TOP_PADDING == 25 && -z $SLIVERBAR_CONFIG ]]
'
printf 'SLIVERBAR_CONFIG=""\n' >"$fixture/hosts/Ikarus2/profile.sh"
# shellcheck disable=SC2016
env -i HOME="$HOME" PATH="$PATH" BSPWM_CONFIG_DIR="$fixture" BSPWM_HOST_OVERRIDE=IKARUS2 bash -eu -c '
    source "$BSPWM_CONFIG_DIR/lib/host-profile.sh"
    [[ $SLIVERBAR_CONFIG == "$BSPWM_HOST_DIR/sliverbar.conf" ]]
    rm "$BSPWM_HOST_DIR/sliverbar.conf"
    unset BSPWM_HOST_PROFILE_LOADED
    source "$BSPWM_CONFIG_DIR/lib/host-profile.sh"
    [[ -z $SLIVERBAR_CONFIG ]]
'
[[ $(load_profile PeGaSuS4) == "Pegasus4|desktop|25|1" ]]
[[ $(load_profile IKARUS2) == "Ikarus2|laptop|25|1" ]]
for invalid in Ikarus ikarus ../Ikarus2; do
    load_profile "$invalid" 2>"$fixture/diagnostic" >/dev/null
    [[ -s $fixture/diagnostic ]]
done
[[ $BSPWM_WALLPAPER == "$HOME/Bilder/Wallpaper/sixtinische-haende-unicode-wallpaper-3840x1600.png" ]]
[[ $BSPWM_INTERNAL_OUTPUT == eDP-1 && $BSPWM_EXTERNAL_OUTPUT == HDMI-1 ]]

# shellcheck disable=SC2016
env -i HOME="$HOME" PATH="$PATH" BSPWM_CONFIG_DIR="$repository_root" BSPWM_HOST_OVERRIDE=Pegasus4 bash -eu -c '
    source "$BSPWM_CONFIG_DIR/lib/host-profile.sh"
    [[ $BSPWM_WALLPAPER == "$HOME/Bilder/Wallpaper/Background.jpg" ]]
    [[ -z $BSPWM_INTERNAL_OUTPUT && -z $BSPWM_EXTERNAL_OUTPUT ]]
    [[ $BSPWM_ENABLE_AUTOLOCK == 1 && $BSPWM_ENABLE_SCREEN_LOCK == 1 ]]
'
printf 'host profile tests passed\n'
