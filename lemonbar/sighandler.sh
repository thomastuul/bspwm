#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

if [[ ${DEBUG-} =~ ^(1|yes|true)$ ]]; then
    set -o xtrace
fi

# shellcheck source=config.sh
source "$LEMONDIR/config.sh"
declare -F log_error >/dev/null || {
    printf 'logging bootstrap not loaded: %s\n' "${BASH_ENV:-unset}" >&2
    exit 1
}

pid=""
spid=""
network_worker_pid=""
weather_worker_pid=""
network_worker_started=0
weather_worker_started=0

stop_child() {
    local child_pid=${1:-}
    [[ $child_pid =~ ^[0-9]+$ ]] || return 0
    kill -TERM "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
}

trap_cleanup() {
    trap - INT TERM QUIT EXIT HUP ERR
    stop_child "$weather_worker_pid"
    stop_child "$network_worker_pid"
    stop_child "$spid"
    log_info "cleanup"
}
trap trap_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 0' QUIT HUP

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

update_block() {
    local target=$1 block_name=$2 output rc
    shift 2
    [[ $target =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 2
    if output=$("$@"); then
        printf -v "$target" '%s' "$output"
    else
        rc=$?
        log_error "block update failed: name=$block_name rc=$rc"
    fi
}

cache_is_fresh() {
    local cache=$1 max_age=${2:-300} modified now
    [[ -r $cache ]] || return 1
    modified=$(stat -c %Y -- "$cache" 2>/dev/null) || return 1
    now=$EPOCHSECONDS
    ((now >= modified && now - modified <= max_age))
}

update_cache_block() {
    local target=$1 display_cache=$2 stale_value=${3:-}
    [[ $target =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 2
    if cache_is_fresh "$display_cache" "$CACHE_STALE_MAX_AGE"; then
        printf -v "$target" '%s' "$(<"$display_cache")"
    elif [[ -n $stale_value ]]; then
        printf -v "$target" '%s' "$stale_value"
    else
        printf -v "$target" '%s' ""
    fi
}

cpu() { update_block cpu_string cpu "$LEMONDIR/modules/block_cpu.sh"; }
clock() { update_block clock_string clock "$LEMONDIR/modules/block_clock.sh"; }
wsindicator() { update_block ws_string workspace "$LEMONDIR/modules/block_wsindicator.sh"; }
window_title() { update_cache_block title_string "$tmp_dir/lemonbar_title.cache"; }
launcher() { update_block launch_string launcher "$LEMONDIR/modules/block_launcher.sh"; }
power() { update_block power_string power "$LEMONDIR/modules/block_power.sh"; }
volume() { update_block vol_string volume "$LEMONDIR/modules/block_volume.sh" "$1"; }
monitor() { update_block mon_string brightness "$LEMONDIR/modules/block_brightness.sh" "$1" "$2"; }
tray() { update_block tray_string tray "$LEMONDIR/modules/block_trayer.sh"; }
network() {
    local cache_root=${XDG_CACHE_HOME:-$HOME/.cache}
    update_cache_block net_string "${NETWORK_CACHE_DIR:-$cache_root/lemonbar}/network.cache"
}
battery() { update_block battery_string battery "$LEMONDIR/modules/block_battery.sh"; }
screencast() { update_block cast_string screencast "$LEMONDIR/modules/block_screencast.sh"; }
weather() {
    local cache_root=${XDG_CACHE_HOME:-$HOME/.cache}
    update_cache_block weather_string "${WEATHERREPORT:-$cache_root/weather}/lemonbar.cache"
}

start_network_worker() {
    bash "$LEMONDIR/network_worker.sh" "$pid" &
    network_worker_pid=$!
    network_worker_started=$EPOCHSECONDS
    log_info "worker started: name=network pid=$network_worker_pid"
}

start_weather_worker() {
    "$LEMONDIR/weather_worker.sh" "$pid" &
    weather_worker_pid=$!
    weather_worker_started=$EPOCHSECONDS
    log_info "worker started: name=weather pid=$weather_worker_pid"
}

ensure_workers() {
    local now=$EPOCHSECONDS
    if ! [[ $network_worker_pid =~ ^[0-9]+$ ]] || ! kill -0 "$network_worker_pid" 2>/dev/null; then
        if [[ -n $network_worker_pid ]]; then
            wait "$network_worker_pid" 2>/dev/null || true
            log_error "worker stopped: name=network pid=$network_worker_pid"
        fi
        network_worker_pid=""
        if ((now - network_worker_started >= WORKER_RESTART_DELAY)); then
            start_network_worker
        fi
    fi
    if ! [[ $weather_worker_pid =~ ^[0-9]+$ ]] || ! kill -0 "$weather_worker_pid" 2>/dev/null; then
        if [[ -n $weather_worker_pid ]]; then
            wait "$weather_worker_pid" 2>/dev/null || true
            log_error "worker stopped: name=weather pid=$weather_worker_pid"
        fi
        weather_worker_pid=""
        if ((now - weather_worker_started >= WORKER_RESTART_DELAY)); then
            start_weather_worker
        fi
    fi
}

tick_count=0
tick() {
    tick_count=$((tick_count + 1))
    clock
    if ((tick_count % 5 == 0)); then cpu; fi
    if ((tick_count % 10 == 0)); then battery; fi
    if ((tick_count % 60 == 0)); then weather; fi
}

pending_tick=0
pending_workspace=0
pending_title=0
pending_volume=0
pending_brightness=0
pending_tray=0
pending_network=0
pending_screencast=0

process_pending_updates() {
    local brightness_delta
    if ((pending_tick)); then pending_tick=0; tick; fi
    if ((pending_workspace)); then pending_workspace=0; wsindicator; fi
    if ((pending_title)); then pending_title=0; window_title; fi
    if ((pending_volume)); then pending_volume=0; volume "$pid"; fi
    if ((pending_brightness != 0)); then
        brightness_delta=$pending_brightness
        pending_brightness=0
        monitor "$brightness_delta" "$pid"
    fi
    if ((pending_tray)); then pending_tray=0; tray; fi
    if ((pending_network)); then pending_network=0; network; fi
    if ((pending_screencast)); then pending_screencast=0; screencast; fi
}

updates_pending() {
    ((pending_tick || pending_workspace || pending_title || pending_volume ||
        pending_brightness != 0 || pending_tray || pending_network ||
        pending_screencast))
}

debounce_signals() {
    local wait_status
    sleep "$SIGNAL_DEBOUNCE_DELAY" &
    spid=$!
    while true; do
        if wait "$spid" 2>/dev/null; then break; else wait_status=$?; fi
        ((wait_status > 128)) || break
    done
    spid=""
}

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

    pid=$BASHPID
    start_network_worker
    start_weather_worker

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
        ensure_workers
        now=$EPOCHSECONDS
        if ((now >= next_tick)); then
            next_tick=$((now + 1))
            tick
        fi
        process_pending_updates
        render_line

        if updates_pending; then
            debounce_signals
            continue
        fi

        sleep 1 &
        spid=$!
        if wait "$spid"; then wait_rc=0; else wait_rc=$?; fi
        kill "$spid" 2>/dev/null || true
        spid=""
        if ((wait_rc != 0)); then
            debounce_signals
        fi
    done
}

main
