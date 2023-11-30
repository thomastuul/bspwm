#!/usr/bin/env bash

set -o errexit      # Exit on most errors (see the manual)
set -o nounset      # Disallow expansion of unset variables
set -o pipefail     # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
set -o errtrace     # Ensure the error trap handler is inherited

dummy() {
    :
}

seconds=0

while true; do
    # every second
    pkill -RTMIN+3 sighandler.sh
    pkill -RTMIN+4 sighandler.sh

    # every 5 seconds
    if [[ $((seconds % 5)) -eq 0 ]]; then
        pkill -RTMIN+3 sighandler.sh
        pkill -RTMIN+4 sighandler.sh
    fi

    # every 10 seconds
    if [[ $((seconds % 10)) -eq 0 ]]; then
        dummy
    fi

    # every 60 seconds
    if [[ $((seconds % 60)) -eq 0 ]]; then
        pkill -RTMIN+10 sighandler.sh
    fi

    seconds=$((seconds+1))
    sleep 1
done
