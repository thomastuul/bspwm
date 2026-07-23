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
if ! declare -F log_error >/dev/null; then
    printf 'logging bootstrap not loaded: %s\n' "${BASH_ENV:-unset}" >&2
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

# Stop and reap the producer owned by the current listener subshell.
cleanup_listener_producer() {
    trap - INT TERM HUP

    if [[ -n "${listener_producer_pid:-}" ]]; then
        kill -TERM "$listener_producer_pid" 2>/dev/null || true
        wait "$listener_producer_pid" 2>/dev/null || true
    fi
}

# Send a workspace update signal for all relevant bspwm events.
get_ws_updates() {
    listener_producer_pid=""
    trap 'cleanup_listener_producer; exit 0' INT TERM HUP

    # The report stream covers every state change represented by the workspace
    # indicator, including desktop, monitor, occupancy and urgency changes.
    coproc EVENT_SOURCE {
        exec stdbuf -oL -eL bspc subscribe report
    }
    listener_producer_pid=$EVENT_SOURCE_PID

    while IFS= read -r <&"${EVENT_SOURCE[0]}"; do
        kill -s "$SIGNAL_WORKSPACE" "$sighandler_pid" 2>/dev/null || break
    done

    cleanup_listener_producer
}

get_trayer_updates() {
    local current_width hints line new_width

    listener_producer_pid=""
    trap 'cleanup_listener_producer; exit 0' INT TERM HUP

    # Wait until the Trayer window exposes a valid minimum width. Keep the
    # expected xprop failure inside the conditional so errexit does not fire.
    while :; do
        current_width=""
        if hints=$(LC_ALL=C xprop -name "$SYSTRAY_WM_NAME" WM_NORMAL_HINTS 2>/dev/null) &&
            [[ $hints =~ program\ specified\ minimum\ size:[[:space:]]*([0-9]+) ]]; then
            current_width=${BASH_REMATCH[1]}
        fi

        if [[ $current_width =~ ^[0-9]+$ ]]; then
            break
        fi

        kill -0 "$sighandler_pid" 2>/dev/null || return
        sleep 0.1
    done

    # Request one initial update after the Trayer window is ready.
    kill -s "$SIGNAL_TRAY" "$sighandler_pid" 2>/dev/null || return

    coproc EVENT_SOURCE {
        exec env LC_ALL=C stdbuf -oL -eL \
            xprop -name "$SYSTRAY_WM_NAME" -spy WM_NORMAL_HINTS
    }
    listener_producer_pid=$EVENT_SOURCE_PID

    while IFS= read -r line <&"${EVENT_SOURCE[0]}"; do
        [[ "$line" == *'program specified minimum size'* ]] || continue

        new_width=${line#*: }
        new_width=${new_width%% *}

        [[ $new_width =~ ^[0-9]+$ ]] || continue
        [[ $new_width == "$current_width" ]] && continue
        current_width=$new_width

        kill -s "$SIGNAL_TRAY" "$sighandler_pid" 2>/dev/null || break
        sleep 0.05
        # Refresh workspaces after applications enter or leave the tray.
        kill -s "$SIGNAL_WORKSPACE" "$sighandler_pid" 2>/dev/null || break
    done

    cleanup_listener_producer
}

get_ws_updates &
listener_pids+=("$!")

get_trayer_updates &
listener_pids+=("$!")

# Keep the event supervisor alive while its signal receiver exists.
# If sighandler.sh disappears, leaving this script running would retain stale
# event listeners that continue sending signals to an obsolete PID.
while kill -0 "$sighandler_pid" 2>/dev/null; do
    sleep 2
done

log_error "sighandler stopped: pid=$sighandler_pid"
exit 1
