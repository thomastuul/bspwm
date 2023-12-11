#!/usr/bin/env bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

#set -o errexit      # Exit on most errors (see the manual)
#set -o nounset      # Disallow expansion of unset variables
#set -o pipefail     # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
#set -o errtrace     # Ensure the error trap handler is inherited

source "$LEMONDIR/config.sh"

name=""
run="rofi -no-config -no-lazy-grab -show drun -modi drun -theme ~/.config/bspwm/rofi/launcher.rasi"

launcher="%{A:$run:}%{F$COLOR_DEFAULT_FG}%{B$COLOR_DEFAULT_BG} ${name}$PADDING%{B-}%{F-}%{A}"

printf "%s" "$launcher"

# vim: syntax=bash
