#!/bin/bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace # Trace the execution of the script (debug)
fi

#set -o errexit      # Exit on most errors (see the manual)
set -o nounset  # Disallow expansion of unset variables
set -o pipefail # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
set -o errtrace # Ensure the error trap handler is inherited

source "$LEMONDIR/config.sh"

# shellcheck disable=SC1090
if [[ -r "$BASH_ENV" ]]; then
    # shellcheck source=lib/logging_env.sh
    source "$BASH_ENV"
else
    echo "logging_env.sh not found at: $BASH_ENV" >&2
fi

# check parameter count
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <sighandler_pid>" >&2
    exit 1
fi

sighandler_pid=$1

# shellcheck disable=SC2154
title_fifo="$tmp_dir/lemonbar_title.fifo"

# DESC: Remove FIFO
# ARGS: None
# OUTS: None
trap_cleanup() {
    # Disable the termination trap handler to prevent potential recursion
    trap - TERM
    if [[ -e "$title_fifo" ]]; then
        rm -f "$title_fifo"
    fi
}

# DESC: Errorhandler
# ARGS: $1: Exit status code
# OUTS: None
trap_err() {
    local code="$1"
    if [[ ${code:-} -eq 143 ]]; then return 0; fi # xtmon.sh ends with 143 at stop
}

trap 'trap_cleanup' EXIT INT TERM QUIT HUP

# create named pipe
if [[ -e "$title_fifo" ]]; then
    rm -f "$title_fifo"
fi
mkfifo -m 600 "$title_fifo"

# DESC: Check if given PID variable is a valid, running process
# ARGS: $1 (string) PID value to check
# OUTS: 0 if valid PID of running process, 1 otherwise
check_pid() {
    local pid="$1"

    # must be a non-empty string of digits
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1

    # test if process exists
    if kill -0 "$pid" 2>/dev/null; then
        return 0
    fi

    return 1
}

if [[ -n "${sighandler_pid-}" ]] && check_pid "$sighandler_pid"; then
    echo "PID $sighandler_pid ist gültig und Prozess läuft"
else
    echo "PID sighandler_pid ungültig oder Prozess existiert nicht"
    exit 1
fi

# DESC: Get title of active window
# ARGS: None
# OUTS: None
activeWindow() {
    "$LEMONDIR/xtmon.sh" | while IFS= read -r line; do
        if ! kill -s SIGRTMIN+5 "$sighandler_pid" 2>/dev/null; then
            log_error "sighandler not running: pid=$sighandler_pid"
            break
        fi

        # Give block_title_client.sh time to open the FIFO for reading.
        sleep 0.02

        truncated="$(
            printf '%s\n' "$line" |
                awk -v m="$TITLE_MAX_LENGHT" '{print substr($0,1,m)}'
        )"

        printf '%s\n' \
            "%{B$COLOR_DEFAULT_BG}%{F$COLOR_FREE_FG}%{+u}$PADDING$truncated$PADDING%{-u}%{F-}%{B-}" \
            >"$title_fifo"
    done
}

activeWindow
