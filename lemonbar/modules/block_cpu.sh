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

calculate() {
  echo "scale=2; $*" | bc | awk '{printf "%2.1f", $0}'
}

# shellcheck disable=SC1091
source "$LEMONDIR/config.sh"

LOADAVG=$(cut -d ' ' -f1 /proc/loadavg)
NUM_CORES=$(nproc --all)

icon=""
RESULT=$(calculate "$LOADAVG * 100")
load=$(calculate "$RESULT / $NUM_CORES")

printf "%s" "%{A1:/bin/sh -c 'setsid -f \"$TERMINAL\" -e sh -c btop >/dev/null 2>&1 &':}%{B$COLOR_DEFAULT_BG}%{F$COLOR_SYS_FG}%{+u} $icon ${load}% %{-u}%{F-}%{B-}%{A}"
