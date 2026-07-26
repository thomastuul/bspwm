#!/usr/bin/env bash
# Load generic bspwm defaults and an optional machine-specific profile.
# The assignments are consumed by scripts that source this library.
# shellcheck disable=SC2034

if [[ ${BSPWM_HOST_PROFILE_LOADED:-0} == 1 ]]; then
    return 0
fi

BSPWM_CONFIG_DIR="${BSPWM_CONFIG_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
BSPWM_HOST_NAME="${BSPWM_HOST_OVERRIDE:-$(hostname -s 2>/dev/null || hostname)}"

case ${BSPWM_HOST_NAME,,} in
    ikarus | ikarus2)
        BSPWM_HOST_NAME=Ikarus
        ;;
    pegasus4)
        BSPWM_HOST_NAME=Pegasus4
        ;;
esac

BSPWM_HOST_ROLE=generic
BSPWM_TOP_PADDING=25
BSPWM_WALLPAPER="${HOME}/Bilder/Wallpaper/Background.jpg"
BSPWM_ENABLE_SLIVERBAR=1
BSPWM_ENABLE_CONKY=1
BSPWM_ENABLE_BLUEMAN=1
BSPWM_ENABLE_NEXTCLOUD=1
BSPWM_ENABLE_SCREEN_LOCK=1
BSPWM_ENABLE_AUTOLOCK=1
BSPWM_ENABLE_PICOM=1
SLIVERBAR_CONFIG=""

BSPWM_HOST_DIR="${BSPWM_CONFIG_DIR}/hosts/${BSPWM_HOST_NAME}"
BSPWM_HOST_PROFILE="${BSPWM_HOST_DIR}/profile.sh"
if [[ -r $BSPWM_HOST_PROFILE ]]; then
    # shellcheck source=/dev/null
    source "$BSPWM_HOST_PROFILE"
fi

if [[ -z $SLIVERBAR_CONFIG && -r $BSPWM_HOST_DIR/sliverbar.conf ]]; then
    SLIVERBAR_CONFIG="$BSPWM_HOST_DIR/sliverbar.conf"
fi

BSPWM_HOST_PROFILE_LOADED=1
export BSPWM_CONFIG_DIR BSPWM_HOST_DIR BSPWM_HOST_NAME BSPWM_HOST_ROLE
export BSPWM_WALLPAPER
if [[ -n $SLIVERBAR_CONFIG ]]; then
    export SLIVERBAR_CONFIG
else
    export -n SLIVERBAR_CONFIG
fi

bspwm_feature_enabled() {
    local variable=$1 value
    value=${!variable:-0}

    case ${value,,} in
        1 | true | yes | on | enabled)
            return 0
            ;;
        0 | false | no | off | disabled | "")
            return 1
            ;;
        *)
            printf 'bspwm: invalid value %q for %s\n' "$value" "$variable" >&2
            return 1
            ;;
    esac
}
