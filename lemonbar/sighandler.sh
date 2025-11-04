#!/usr/bin/env bash

set -o errexit  # Exit on most errors (see the manual)
set -o nounset  # Disallow expansion of unset variables
set -o pipefail # Use last non-zero exit code in a pipeline
set -o errtrace # Ensure the error trap handler is inherited

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace # Trace the execution of the script (debug)
fi

# shellcheck disable=SC1090
if [[ -r "${BASH_ENV:-}" ]]; then
    # shellcheck source=lib/logging_env.sh
    source "$BASH_ENV"
fi

# DESC: Terminate subprocesses
# ARGS: None
# OUTS: None
trap_cleanup() {
    # prevent reentrancy
    trap - INT TERM QUIT EXIT HUP ERR
    # nur Kindprozesse beenden, niemals die eigene Shell
    if [[ -n ${spid-} ]]; then
        kill "$spid" 2>/dev/null || true
    fi
    pkill -P "$$" 2>/dev/null || true
    wait 2>/dev/null || true
    log_info "cleanup"
}

trap 'trap_cleanup' EXIT INT TERM QUIT HUP

cpu() { cpu_string="$("$LEMONDIR"/modules/block_cpu.sh)"; }
clock() { clock_string="$("$LEMONDIR"/modules/block_clock.sh)"; }
wsindicator() { ws_string="$("$LEMONDIR"/modules/block_wsindicator.sh)"; }
window_title() { title_string="$("$LEMONDIR"/modules/block_title_client.sh)"; }
launcher() { launch_string="$("$LEMONDIR"/modules/block_launcher.sh)"; }
power() { power_string="$("$LEMONDIR"/modules/block_power.sh)"; }
volume() { vol_string="$("$LEMONDIR"/modules/block_volume.sh "$1")"; }
monitor() { mon_string="$("$LEMONDIR"/modules/block_brightness.sh "$1" "$2")"; }
tray() { tray_string="$("$LEMONDIR"/modules/block_trayer.sh)"; }
network() { net_string="$("$LEMONDIR"/modules/block_network.sh)"; }
battery() { battery_string="$("$LEMONDIR"/modules/block_battery.sh)"; }
screencast() { cast_string="$("$LEMONDIR"/modules/block_screencast.sh)"; }
weather() { weather_string="$("$LEMONDIR"/modules/block_weather.sh)"; }

# DESC: Initialize signals, print lemonbar strings
# ARGS: $1 (required): Message to print (defaults to a green foreground)
#       $2 (optional): Colour to print the message with. This can be an ANSI
#                      escape code or one of the prepopulated colour variables.
#       $3 (optional): Set to any value to not append a new line to the message
# OUTS: None
sig_init() {
    trap -- 'call_or_log wsindicator' SIGRTMIN+2
    trap -- 'call_or_log cpu; call_or_log clock' SIGRTMIN+3
    trap -- 'call_or_log window_title' SIGRTMIN+5
    trap -- 'call_or_log volume "$pid"' SIGRTMIN+6
    trap -- 'call_or_log monitor "+" "$pid"' SIGRTMIN+7
    trap -- 'call_or_log monitor "-" "$pid"' SIGRTMIN+8
    trap -- 'call_or_log tray' SIGRTMIN+9
    trap -- 'call_or_log network; battery' SIGRTMIN+10
    trap -- 'call_or_log screencast' SIGRTMIN+11
    trap -- 'call_or_log weather' SIGRTMIN+12

    # own PID
    pid="$BASHPID"

    LOGGING_ENV_AUTO=1 "$LEMONDIR"/scheduler.sh "$pid" &

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
    printf "%s" \
        "%{l}${launch_string}${ws_string}" \
        "%{c}${title_string}" \
        "%{r}${cast_string}${weather_string}${battery_string}${net_string}${mon_string}${vol_string}${cpu_string}${clock_string}${tray_string}${power_string}"
}

main() {
    sig_init
    while true; do
        render_line
        sleep infinity &
        spid=$!
        wait "$spid" || true
        kill "$spid" 2>/dev/null || true
    done
}

main
