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

LOADAVG=$(cut -d ' ' -f1 /proc/loadavg)
NUM_CORES=$(nproc --all)
load=$(awk -v l="$LOADAVG" -v c="$NUM_CORES" 'BEGIN{printf "%2.1f", (l*100)/c}')

icon=""

printf "%s" "%{A1:/bin/sh -c 'setsid -f \"$TERMINAL\" -e sh -c btop >/dev/null 2>&1 &':}%{B$COLOR_DEFAULT_BG}%{F$COLOR_SYS_FG}%{+u} $icon ${load}% %{-u}%{F-}%{B-}%{A}"
