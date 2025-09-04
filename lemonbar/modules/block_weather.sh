#!/usr/bin/env bash
set -x
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
Weather="$("$HOME/.config/bspwm/bin/sb-forecast.sh" "München")"
age_text="$("$HOME/.config/bspwm/bin/sb-forecast.sh" München age)"
msg="Update vor ${age_text} min"
run_right="notify-send $(printf %q "$msg")"

# Left-click (Button 1): Terminal mit wttr.in
run_left="$HOME/.config/bspwm/bin/open-wttr.sh &"

printf "%s\n" "%{A1:$run_left:}%{A3:$run_right:}%{B$COLOR_DEFAULT_BG}%{F$COLOR_WEATHER_FG}%{+u} ${Weather}%{-u}%{F-}%{B-}%{A}%{A}"
