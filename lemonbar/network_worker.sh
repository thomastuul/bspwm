#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ ${DEBUG-} =~ ^(1|yes|true)$ ]]; then
    set -o xtrace
fi

# shellcheck source=config.sh
source "$LEMONDIR/config.sh"
# shellcheck disable=SC1090
if [[ -n ${BASH_ENV:-} && -r $BASH_ENV ]]; then
    # shellcheck source=lib/logging_env.sh
    source "$BASH_ENV"
else
    printf 'logging_env.sh not found: %s\n' "${BASH_ENV:-unset}" >&2
    exit 1
fi

if [[ $# -ne 1 || ! $1 =~ ^[0-9]+$ ]]; then
    printf 'Usage: %s <sighandler_pid>\n' "$0" >&2
    exit 2
fi

sighandler_pid=$1
refresh_interval="${NETWORK_REFRESH_INTERVAL:-60}"
[[ $refresh_interval =~ ^[1-9][0-9]*$ ]] || refresh_interval=60

cache_root="${XDG_CACHE_HOME:-$HOME/.cache}"
network_cache_dir="${NETWORK_CACHE_DIR:-$cache_root/lemonbar}"
display_cache="$network_cache_dir/network.cache"
display_cache_tmp="$display_cache.${BASHPID}"
monitor_pid=""
monitor_fd=""

cleanup_monitor() {
    if [[ $monitor_pid =~ ^[0-9]+$ ]]; then
        kill -TERM "$monitor_pid" 2>/dev/null || true
        wait "$monitor_pid" 2>/dev/null || true
    fi
    monitor_pid=""
    monitor_fd=""
}

cleanup() {
    trap - EXIT INT TERM HUP
    cleanup_monitor
    rm -f -- "$display_cache_tmp"
}

trap cleanup EXIT
trap 'exit 0' INT TERM HUP

publish_network() {
    local output current=""

    if ! output=$(bash "$LEMONDIR/modules/block_network.sh" --refresh); then
        log_error "network refresh failed"
        return 0
    fi

    if [[ -r $display_cache ]]; then
        current=$(<"$display_cache")
    fi
    [[ $output != "$current" ]] || return 0

    mkdir -p -- "$network_cache_dir"
    printf '%s\n' "$output" >"$display_cache_tmp"
    mv -f -- "$display_cache_tmp" "$display_cache"

    if ! kill -s "$SIGNAL_NETWORK" "$sighandler_pid" 2>/dev/null; then
        exit 0
    fi
}

start_monitor() {
    coproc NETWORK_EVENTS {
        exec env LC_ALL=C stdbuf -oL -eL nmcli monitor
    }
    monitor_pid=$NETWORK_EVENTS_PID
    monitor_fd=${NETWORK_EVENTS[0]}
}

publish_network

while kill -0 "$sighandler_pid" 2>/dev/null; do
    if ! command -v nmcli >/dev/null 2>&1; then
        sleep "$refresh_interval"
        publish_network
        continue
    fi

    start_monitor

    while kill -0 "$sighandler_pid" 2>/dev/null; do
        if IFS= read -r -t "$refresh_interval" <&"$monitor_fd"; then
            # Coalesce bursts of NetworkManager notifications.
            sleep 0.2
            while IFS= read -r -t 0.01 <&"$monitor_fd"; do
                :
            done
            publish_network
        elif kill -0 "$monitor_pid" 2>/dev/null; then
            # No event arrived: perform the periodic fallback refresh.
            publish_network
        else
            cleanup_monitor
            sleep 1
            break
        fi
    done
done
