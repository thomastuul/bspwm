#!/usr/bin/env bash

export LC_ALL=C

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace # Trace the execution of the script (debug)
fi

set -o errexit  # Exit on most errors (see the manual)
set -o nounset  # Disallow expansion of unset variables
set -o pipefail # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
set -o errtrace # Ensure the error trap handler is inherited

source "${LEMONDIR}/config.sh"
# shellcheck disable=SC1090
if [[ -n "${BASH_ENV:-}" && -r "$BASH_ENV" ]]; then
    # shellcheck source=lib/logging_env.sh
    source "$BASH_ENV"
else
    exit 1
fi

trap_exit() {
    kill "$(jobs -pr)" 2>/dev/null || true
}

trap 'trap_exit' EXIT
trap 'trap_exit; exit 0' INT TERM HUP

# check parameter count
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <sighandler_pid>" >&2
    exit 1
fi

sighandler_pid=$1

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

if check_pid "$sighandler_pid"; then
    echo "PID $sighandler_pid ist gültig und Prozess läuft"
else
    echo "PID $sighandler_pid ungültig oder Prozess existiert nicht"
    exit 1
fi

# Send signal for update lemonbar workspaces at event desktop change
get_ws_updates_changed_desktop() {
    stdbuf -oL -eL bspc subscribe desktop_focus | while read -r; do
        # shellcheck disable=SC2154
        kill -s SIGRTMIN+2 "$sighandler_pid" || true
    done
}

# Send signal for update lemonbar workspaces at event node transfer to different desktop
get_ws_updates_node_transfer() {
    stdbuf -oL -eL bspc subscribe node_transfer | while read -r; do
        kill -s SIGRTMIN+2 "$sighandler_pid" || true
    done
}

# Send signal for update lemonbar workspaces at layout change
get_ws_updates_layout_change() {
    stdbuf -oL -eL bspc subscribe desktop_layout | while read -r; do
        kill -s SIGRTMIN+2 "$sighandler_pid" || true
    done
}

get_trayer_updates() {
    # wait until trayer has started
    while ! pidof trayer >/dev/null; do
        sleep 0.1
    done

    stdbuf -oL -eL xprop -name "$SYSTRAY_WM_NAME" -spy | grep --line-buffered 'program specified minimum size' | while IFS= read -r; do
        sleep 0.02
        kill -s SIGRTMIN+9 "$sighandler_pid" || true
        sleep 0.02
        # often an app disappears from workspace too if it is gone from systray
        kill -s SIGRTMIN+2 "$sighandler_pid" || true
    done
}

get_new_node_updates() {
    stdbuf -oL -eL bspc subscribe node_add | while read -r; do
        kill -s SIGRTMIN+2 "$sighandler_pid" || true
    done
}

get_ws_updates_changed_desktop &
get_ws_updates_node_transfer &
get_ws_updates_layout_change &
get_trayer_updates &
get_new_node_updates &
