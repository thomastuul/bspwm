#!/usr/bin/env bash

set -o errexit  # Exit on most errors (see the manual)
set -o nounset  # Disallow expansion of unset variables
set -o pipefail # Use last non-zero exit code in a pipeline
set -o errtrace # Ensure the error trap handler is inherited

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace # Trace the execution of the script (debug)
fi

# Load the shared signal map before installing realtime signal traps.
# shellcheck source=config.sh
source "$LEMONDIR/config.sh"

if ! declare -F log_error >/dev/null; then
    printf 'logging bootstrap not loaded: %s\n' "${BASH_ENV:-unset}" >&2
    exit 1
fi

# DESC: Terminate subprocesses
# ARGS: None
# OUTS: None
trap_cleanup() {
    # prevent reentrancy
    trap - INT TERM QUIT EXIT HUP ERR
    # Stop explicitly managed background workers before leaving.
    if [[ ${weather_worker_pid:-} =~ ^[0-9]+$ ]]; then
        kill -TERM "$weather_worker_pid" 2>/dev/null || true
        wait "$weather_worker_pid" 2>/dev/null || true
    fi
    if [[ ${network_worker_pid:-} =~ ^[0-9]+$ ]]; then
        kill -TERM "$network_worker_pid" 2>/dev/null || true
        wait "$network_worker_pid" 2>/dev/null || true
    fi
    if [[ -n ${spid-} ]]; then
        kill -TERM "$spid" 2>/dev/null || true
        wait "$spid" 2>/dev/null || true
    fi
    log_info "cleanup"
}

trap 'trap_cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 0' QUIT HUP

# Initial values keep render_line safe even if every module fails at startup.
cpu_string=""
clock_string=" --:--:-- "
ws_string=""
title_string=""
launch_string=""
power_string=""
vol_string=""
mon_string=""
tray_string=""
net_string=""
battery_string=""
cast_string=""
weather_string=""

# Update one module without replacing its last valid output on failure.
update_block() {
    local target=$1 block_name=$2
    local output rc
    shift 2

    [[ $target =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 2

    if output=$("$@"); then
        printf -v "$target" '%s' "$output"
    else
        rc=$?
        log_error "block update failed: name=$block_name rc=$rc"
    fi

    return 0
}

# Read worker output without discarding an existing value if the cache is absent.
update_cache_block() {
    local target=$1 display_cache=$2

    [[ $target =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 2

    if [[ -r $display_cache ]]; then
        printf -v "$target" '%s' "$(<"$display_cache")"
    fi

    return 0
}

cpu() {
    update_block cpu_string cpu "$LEMONDIR/modules/block_cpu.sh"
}
clock() {
    update_block clock_string clock "$LEMONDIR/modules/block_clock.sh"
}
wsindicator() {
    update_block ws_string workspace "$LEMONDIR/modules/block_wsindicator.sh"
}
window_title() {
    local title_cache

    # tmp_dir is exported by start.sh and shared with title_server.sh.
    # shellcheck disable=SC2154
    title_cache="$tmp_dir/lemonbar_title.cache"
    update_cache_block title_string "$title_cache"
}
launcher() {
    update_block launch_string launcher "$LEMONDIR/modules/block_launcher.sh"
}
power() {
    update_block power_string power "$LEMONDIR/modules/block_power.sh"
}
volume() {
    update_block vol_string volume "$LEMONDIR/modules/block_volume.sh" "$1"
}
monitor() {
    update_block mon_string brightness "$LEMONDIR/modules/block_brightness.sh" "$1" "$2"
}
tray() {
    update_block tray_string tray "$LEMONDIR/modules/block_trayer.sh"
}
network() {
    local cache_root network_cache_dir display_cache

    cache_root="${XDG_CACHE_HOME:-$HOME/.cache}"
    network_cache_dir="${NETWORK_CACHE_DIR:-$cache_root/lemonbar}"
    display_cache="$network_cache_dir/network.cache"

    update_cache_block net_string "$display_cache"
}
battery() {
    update_block battery_string battery "$LEMONDIR/modules/block_battery.sh"
}
screencast() {
    update_block cast_string screencast "$LEMONDIR/modules/block_screencast.sh"
}
weather() {
    local cache_root weather_cache_dir display_cache

    cache_root="${XDG_CACHE_HOME:-$HOME/.cache}"
    weather_cache_dir="${WEATHERREPORT:-$cache_root/weather}"
    display_cache="$weather_cache_dir/lemonbar.cache"

    update_cache_block weather_string "$display_cache"
}

tick_count=0

tick() {
    tick_count=$((tick_count + 1))

    clock

    if ((tick_count % 5 == 0)); then
        cpu
    fi

    if ((tick_count % 10 == 0)); then
        battery
    fi

    if ((tick_count % 60 == 0)); then
        weather
    fi
}

pending_tick=0
pending_workspace=0
pending_title=0
pending_volume=0
pending_brightness=0
pending_tray=0
pending_network=0
pending_screencast=0

# Process updates outside trap context so module calls cannot overlap.
process_pending_updates() {
    local brightness_delta

    if ((pending_tick)); then
        pending_tick=0
        tick
    fi
    if ((pending_workspace)); then
        pending_workspace=0
        wsindicator
    fi
    if ((pending_title)); then
        pending_title=0
        window_title
    fi
    if ((pending_volume)); then
        pending_volume=0
        volume "$pid"
    fi
    if ((pending_brightness != 0)); then
        brightness_delta=$pending_brightness
        pending_brightness=0
        monitor "$brightness_delta" "$pid"
    fi
    if ((pending_tray)); then
        pending_tray=0
        tray
    fi
    if ((pending_network)); then
        pending_network=0
        network
    fi
    if ((pending_screencast)); then
        pending_screencast=0
        screencast
    fi
}

# Return success while at least one signal-triggered update is waiting.
updates_pending() {
    ((pending_tick ||
        pending_workspace ||
        pending_title ||
        pending_volume ||
        pending_brightness != 0 ||
        pending_tray ||
        pending_network ||
        pending_screencast))
}

# Wait for one short collection window while still accepting signal traps.
debounce_signals() {
    local wait_status

    sleep "$SIGNAL_DEBOUNCE_DELAY" &
    spid=$!

    while true; do
        if wait "$spid" 2>/dev/null; then
            break
        else
            wait_status=$?
        fi

        # Signals interrupt wait; other statuses mean the child is gone.
        ((wait_status > 128)) || break
    done
    spid=""
}

# DESC: Initialize signals, print lemonbar strings
# ARGS: $1 (required): Message to print (defaults to a green foreground)
#       $2 (optional): Colour to print the message with. This can be an ANSI
#                      escape code or one of the prepopulated colour variables.
#       $3 (optional): Set to any value to not append a new line to the message
# OUTS: None
sig_init() {
    trap -- 'pending_workspace=1' "$SIGNAL_WORKSPACE"
    trap -- 'pending_tick=1' "$SIGNAL_TICK"
    trap -- 'pending_title=1' "$SIGNAL_TITLE"
    trap -- 'pending_volume=1' "$SIGNAL_VOLUME"
    trap -- 'pending_brightness=$((pending_brightness + 1))' "$SIGNAL_BRIGHTNESS_UP"
    trap -- 'pending_brightness=$((pending_brightness - 1))' "$SIGNAL_BRIGHTNESS_DOWN"
    trap -- 'pending_tray=1' "$SIGNAL_TRAY"
    trap -- 'pending_network=1' "$SIGNAL_NETWORK"
    trap -- 'pending_screencast=1' "$SIGNAL_SCREENCAST"

    # own PID
    pid="$BASHPID"

    # Run network access and weather parsing outside this signal handler.
    bash "$LEMONDIR/network_worker.sh" "$pid" &
    network_worker_pid=$!

    "$LEMONDIR/weather_worker.sh" "$pid" &
    weather_worker_pid=$!

    # init
    window_title
    wsindicator
    cpu
    clock
    launcher
    power
    volume "$pid"
    monitor " " "$pid"
    tray
    network
    screencast
    battery
    weather
}

render_line() {
    printf '%s%s%s\n' \
        "%{l}${launch_string}${ws_string}" \
        "%{c}${title_string}" \
        "%{r}${cast_string}${weather_string}${battery_string}${net_string}${mon_string}${vol_string}${cpu_string}${clock_string}${tray_string}${power_string}"
}

main() {
    local next_tick now wait_rc

    sig_init
    log_info "initialized" "$0"
    next_tick=$((EPOCHSECONDS + 1))

    while true; do
        now=$EPOCHSECONDS
        if ((now >= next_tick)); then
            next_tick=$((now + 1))
            tick
        fi

        process_pending_updates
        render_line

        # Do not sleep with updates that arrived during processing or rendering.
        if updates_pending; then
            debounce_signals
            continue
        fi

        # A finite wait guarantees progress even if a wake-up signal is lost.
        sleep 1 &
        spid=$!
        if wait "$spid"; then
            wait_rc=0
        else
            wait_rc=$?
        fi
        kill "$spid" 2>/dev/null || true
        spid=""

        # A non-zero wait means that an arriving signal interrupted the wait.
        if ((wait_rc != 0)); then
            debounce_signals
        fi
    done
}

main
