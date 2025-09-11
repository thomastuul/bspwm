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

# Signal-Plan:
# RTMIN+3  = CPU   (1s)
# RTMIN+4  = Uhr   (1s)
# RTMIN+5  = Titel (on change)
# RTMIN+10 = Netz/Batt (10s)
# RTMIN+12 = Wetter (60s)

sighandler_pid="$1"

dummy() {
    :
}

seconds=0

while true; do
    # every second
    kill -RTMIN+3 "$sighandler_pid"
    # delay necessary as second kill-signal may drop
    sleep 0.1 || true
    kill -RTMIN+4 "$sighandler_pid"

    # every 5 seconds
    if [[ $((seconds % 5)) -eq 0 ]]; then
        dummy
    fi

    # every 10 seconds
    if [[ $((seconds % 10)) -eq 0 ]]; then
        kill -RTMIN+10 "$sighandler_pid"
    fi

    # every 60 seconds
    if [[ $((seconds % 60)) -eq 0 ]]; then
        kill -RTMIN+12 "$sighandler_pid"
    fi

    seconds=$((seconds+1))
    sleep 1 || true
done
