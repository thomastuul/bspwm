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

if ! declare -F log_error >/dev/null; then
    printf 'logging bootstrap not loaded: %s\n' "${BASH_ENV:-unset}" >&2
    exit 1
fi

# Signal plan:
# SIGRTMIN+3 = periodic tick (1s)
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
        return "$rc"
    fi
}

while true; do
    send_signal SIGRTMIN+3 "$sighandler_pid"
    sleep 1 || true
done
