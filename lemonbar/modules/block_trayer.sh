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

MARGIN="${MARGIN:-4}"

# shellcheck disable=SC1091
source "$LEMONDIR/config.sh"

trayer_width() {
    width=1
    if [[ -n "$(pidof trayer)" ]]; then
        width=$(xprop -name "$SYSTRAY_WM_NAME" | grep 'program specified minimum size' | cut -d ' ' -f 5)
    fi
    printf "%s" "$(( width + MARGIN ))"
}

trayer="%{F$COLOR_DEFAULT_FG}%{B$COLOR_DEFAULT_BG}%{O$(trayer_width)}%{B-}%{F-}"

printf "%s" "$trayer"

# vim: syntax=bash
