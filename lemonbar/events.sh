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

# Store listener PIDs so cleanup only manages processes started by this script.
declare -a listener_pids=()

# ShellCheck cannot detect that cleanup is invoked indirectly by trap.
# shellcheck disable=SC2317
cleanup() {
    # Disable traps first to prevent cleanup from being entered recursively.
    trap - EXIT INT TERM HUP

    # Stop and reap all event listeners to prevent stale background processes.
    if ((${#listener_pids[@]} > 0)); then
        kill -TERM "${listener_pids[@]}" 2>/dev/null || true
        wait "${listener_pids[@]}" 2>/dev/null || true
    fi
}

# Run cleanup on every normal or signal-triggered exit.
trap cleanup EXIT
# Convert termination signals into an exit so the EXIT trap performs cleanup.
trap 'exit 0' INT TERM HUP

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
    log_info "sighandler_pid is valid: PID=" "$sighandler_pid"
else
    log_error "sighandler_pid is invalid: PID=" "$sighandler_pid"
    exit 1
fi

# Send signal for update lemonbar workspaces at event desktop change
get_ws_updates_changed_desktop() {
    stdbuf -oL -eL bspc subscribe desktop_focus | while read -r; do
        # shellcheck disable=SC2154
        kill -s SIGRTMIN+2 "$sighandler_pid" 2>/dev/null || break
    done
}

# Send signal for update lemonbar workspaces at event node transfer to different desktop
get_ws_updates_node_transfer() {
    stdbuf -oL -eL bspc subscribe node_transfer | while read -r; do
        kill -s SIGRTMIN+2 "$sighandler_pid" 2>/dev/null || break
    done
}

# Send signal for update lemonbar workspaces at layout change
get_ws_updates_layout_change() {
    stdbuf -oL -eL bspc subscribe desktop_layout | while read -r; do
        kill -s SIGRTMIN+2 "$sighandler_pid" 2>/dev/null || break
    done
}

get_trayer_updates() {
    # wait until trayer has started
    while ! pidof trayer >/dev/null; do
        sleep 0.1
    done

    stdbuf -oL -eL xprop -name "$SYSTRAY_WM_NAME" -spy | grep --line-buffered 'program specified minimum size' | while IFS= read -r; do
        sleep 0.02
        kill -s SIGRTMIN+9 "$sighandler_pid" 2>/dev/null || break
        sleep 0.02
        # often an app disappears from workspace too if it is gone from systray
        kill -s SIGRTMIN+2 "$sighandler_pid" 2>/dev/null || break
    done
}

get_new_node_updates() {
    stdbuf -oL -eL bspc subscribe node_add | while read -r; do
        kill -s SIGRTMIN+2 "$sighandler_pid" 2>/dev/null || break
    done
}

get_ws_updates_changed_desktop &
listener_pids+=("$!")

get_ws_updates_node_transfer &
listener_pids+=("$!")

get_ws_updates_layout_change &
listener_pids+=("$!")

get_trayer_updates &
listener_pids+=("$!")

get_new_node_updates &
listener_pids+=("$!")

# Keep the event supervisor alive while its signal receiver exists.
# If sighandler.sh disappears, leaving this script running would retain stale
# event listeners that continue sending signals to an obsolete PID.
while kill -0 "$sighandler_pid" 2>/dev/null; do
    sleep 2
done

log_error "sighandler stopped: pid=$sighandler_pid"
exit 1
