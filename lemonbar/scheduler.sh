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

# shellcheck disable=SC1090
if [[ -r "$BASH_ENV" ]]; then
    # shellcheck source=lib/logging_env.sh
    source "$BASH_ENV"
else
    echo "logging_env.sh not found at: $BASH_ENV" >&2
fi

# Signal-Plan:
# SIGRTMIN+3  = CPU/Uhr   (1s)
# SIGRTMIN+5  = Titel     (on change)
# SIGRTMIN+10 = Netz/Batt (10s)
# SIGRTMIN+12 = Wetter    (60s)
sighandler_pid="$1"

send_signal() {
    local signal="$1"
    local pid="$2"
    local rc

    if kill -s "$signal" "$pid" 2>/dev/null; then
        return 0
    else
        rc=$?
        log_error "kill failed: signal=$signal pid=$pid rc=$rc"
        return 0
    fi
}

dummy() {
    :
}

seconds=0

while true; do
    # every second
    send_signal SIGRTMIN+3 "$sighandler_pid"

    # every 5 seconds
    if [[ $((seconds % 5)) -eq 0 ]]; then
        dummy
    fi

    # every 10 seconds
    if [[ $((seconds % 10)) -eq 0 ]]; then
        sleep 0.05
        send_signal SIGRTMIN+10 "$sighandler_pid"
    fi

    # every 60 seconds
    if [[ $((seconds % 60)) -eq 0 ]]; then
        sleep 0.05
        send_signal SIGRTMIN+12 "$sighandler_pid"
    fi

    seconds=$((seconds + 1))
    sleep 1 || true
done
