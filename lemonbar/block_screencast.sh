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

source "$LEMONDIR/config.sh"

if [ -f "$XDG_RUNTIME_DIR/screencast.pid" ]; then
    icon=" 壘"
    color_fg=$COLOR_SCREENCAST_FG
else
    icon=" 壘"
    color_fg=$Selection
fi

printf "%s" "%{B$COLOR_DEFAULT_BG}%{F$color_fg}%{+u}$icon%{-u}%{F-}%{B-}"
