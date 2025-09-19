#!/usr/bin/env bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

set -o errexit      # Exit on most errors (see the manual)
set -o nounset      # Disallow expansion of unset variables
set -o pipefail     # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
set -o errtrace     # Ensure the error trap handler is inherited

# shellcheck disable=SC1091
source "$LEMONDIR/config.sh"

sighandler_pid="$1"

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

# Left-click: open TUI mixer in terminal
vol_ui="/bin/sh -c 'setsid -f \"$TERMINAL\" -e pulsemixer >/dev/null 2>&1 &'"

# Increase volume: prefer pamixer, then pactl, fallback amixer
inc_vol="sh -c 'if command -v pamixer >/dev/null 2>&1; then pamixer -i ${VOL_STEP}; \
elif command -v pactl >/dev/null 2>&1; then pactl set-sink-volume @DEFAULT_SINK@ +${VOL_STEP}%; \
else amixer set Master ${VOL_STEP}%+ >/dev/null; fi; \
kill -RTMIN+6 $sighandler_pid'"

# Decrease volume
dec_vol="sh -c 'if command -v pamixer >/dev/null 2>&1; then pamixer -d ${VOL_STEP}; \
elif command -v pactl >/dev/null 2>&1; then pactl set-sink-volume @DEFAULT_SINK@ -${VOL_STEP}%; \
else amixer set Master ${VOL_STEP}%- >/dev/null; fi; \
kill -RTMIN+6 $sighandler_pid'"

# Toggle mute
vol_toggle="sh -c 'if command -v pamixer >/dev/null 2>&1; then pamixer -t; \
elif command -v pactl >/dev/null 2>&1; then pactl set-sink-mute @DEFAULT_SINK@ toggle; \
else amixer set Master toggle >/dev/null; fi; \
kill -RTMIN+6 $sighandler_pid'"

printf "%s" "%{A1:${vol_ui}:}%{A4:${inc_vol}:}%{A5:${dec_vol}:}%{A3:${vol_toggle}:}$(vol)%{A}%{A}%{A}%{A}"
