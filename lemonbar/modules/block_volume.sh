#!/usr/bin/env bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace # Trace the execution of the script (debug)
fi

set -o errexit  # Exit on most errors (see the manual)
set -o nounset  # Disallow expansion of unset variables
set -o pipefail # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
set -o errtrace # Ensure the error trap handler is inherited

# shellcheck disable=SC1091
source "$LEMONDIR/config.sh"
# shellcheck source=../lib/lemonbar_action.sh
source "$LEMONDIR/lib/lemonbar_action.sh"
# shellcheck disable=SC1090
if [[ -n "${BASH_ENV:-}" && -r "$BASH_ENV" ]]; then
    # shellcheck source=../lib/logging_env.sh
    source "$BASH_ENV"
else
    exit 1
fi

sighandler_pid="$1"
[[ $sighandler_pid =~ ^[0-9]+$ ]] || exit 2

vol() {
    icon_on=""
    icon_off=""
    color_fg_on=$COLOR_VOLUME_FG
    color_fg_off=$COLOR_VOLUME_FG_MUTED
    level=$(amixer get Master | grep -oP '\d+%' | head -n1 | sed 's/%//')
    switched=$(amixer get Master | grep -o -m 1 "\[on\]\|\[off\]" | tr -d '[]')

    if [[ "$switched" == "on" ]]; then
        vol_string="%{B$COLOR_DEFAULT_BG}%{F$color_fg_on}%{+u} $icon_on $level% %{-u}%{F-}%{B-}"
    else
        vol_string="%{B$COLOR_DEFAULT_BG}%{F$color_fg_off}%{+u} $icon_off $level% %{-u}%{F-}%{B-}"
    fi

    printf "%s" "$vol_string"
}

# Volume step in percent (used for scroll up/down)
: "${VOL_STEP:=2}"

# Keep click commands argument-based; the dispatcher validates PID and signal.
vol_ui=$(lemonbar_action \
    bash "$LEMONDIR/lib/click_action.sh" terminal pulsemixer)
inc_vol=$(lemonbar_action \
    bash "$LEMONDIR/lib/click_action.sh" volume increase \
    "$VOL_STEP" "$SIGNAL_VOLUME" "$sighandler_pid")
dec_vol=$(lemonbar_action \
    bash "$LEMONDIR/lib/click_action.sh" volume decrease \
    "$VOL_STEP" "$SIGNAL_VOLUME" "$sighandler_pid")
vol_toggle=$(lemonbar_action \
    bash "$LEMONDIR/lib/click_action.sh" volume toggle \
    "$VOL_STEP" "$SIGNAL_VOLUME" "$sighandler_pid")

printf "%s" "%{A1:${vol_ui}:}%{A4:${inc_vol}:}%{A5:${dec_vol}:}%{A3:${vol_toggle}:}$(vol)%{A}%{A}%{A}%{A}"
