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
# shellcheck disable=SC1090
if [[ -n "${BASH_ENV:-}" && -r "$BASH_ENV" ]]; then
    # shellcheck source=../lib/logging_env.sh
    source "$BASH_ENV"
else
    exit 1
fi

# ensure that trayer is on top of lemonbar
if command -v xdotool >/dev/null 2>&1; then
    if xdotool search --class trayer >/dev/null 2>&1; then
        xdotool search --class trayer windowraise
    fi
fi

MARGIN="${MARGIN:-4}"
SYSTRAY_WM_NAME="${SYSTRAY_WM_NAME:-panel}"

trayer_width() {
    local width=1

    width=$(
        LC_ALL=C xprop -name "$SYSTRAY_WM_NAME" WM_NORMAL_HINTS 2>/dev/null |
            awk '/program specified minimum size/ { print $(NF - 2) }'
    ) || width=1

    [[ $width =~ ^[0-9]+$ ]] || width=1
    printf '%s' "$((width + MARGIN))"
}

trayer="%{F$COLOR_DEFAULT_FG}%{B$COLOR_DEFAULT_BG}%{O$(trayer_width)}%{B-}%{F-}"

printf "%s" "$trayer"

# vim: syntax=bash
