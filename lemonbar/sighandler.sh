#!/usr/bin/env bash

set -o errexit      # Exit on most errors (see the manual)
set -o nounset      # Disallow expansion of unset variables
set -o pipefail     # Use last non-zero exit code in a pipeline
# errtrace must not set here because wait throws errors at every
# reception of a signal

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

log()  { printf '[sighandler] %s\n' "$*" >&2; }

# DESC: Terminate subprocesses
# ARGS: None
# OUTS: None
trap_cleanup() {
    trap - INT TERM QUIT EXIT HUP ERR
    kill "$scheduler_pid"
    wait
    kill "$BASHPID"
    wait
    log "cleanup"
}

# DESC: Errorhandler
# ARGS: $1: If only param -> Exit status code
#           else line number of err occurence.
#       $2: Exit status code
#       $3: invoked command
# OUTS: None
trap_err() {
    local parent_lineno="${1:-?}"
    local code="${2:-?}"
    local cmd="${3:-?}"
    log "ERROR code=${code} at line ${parent_lineno}: ${cmd}"
    return 0
}

trap trap_cleanup INT TERM QUIT EXIT HUP
trap 'trap_err "${LINENO}/${BASH_LINENO}" "$?" "$BASH_COMMAND"'  ERR

cpu()          { cpu_string="$("$LEMONDIR"/modules/block_cpu.sh)"; }
clock()        { clock_string="$("$LEMONDIR"/modules/block_clock.sh)"; }
wsindicator()  { ws_string="$("$LEMONDIR"/modules/block_wsindicator.sh)"; }
# shellcheck disable=SC2154
window_title() { title_string="$(tmp_dir="$tmp_dir" "$LEMONDIR"/modules/block_title_client.sh)"; }
launcher()     { launch_string="$("$LEMONDIR"/modules/block_launcher.sh)"; }
power()        { power_string="$("$LEMONDIR"/modules/block_power.sh)"; }
volume()       { vol_string="$("$LEMONDIR"/modules/block_volume.sh "$1")"; }
monitor()      { mon_string="$("$LEMONDIR"/modules/block_brightness.sh "$1" "$2")"; }
tray()         { tray_string="$("$LEMONDIR"/modules/block_trayer.sh)"; }
network()      { net_string="$("$LEMONDIR"/modules/block_network.sh)"; }
battery()      { battery_string="$("$LEMONDIR"/modules/block_battery.sh)"; }
screencast()   { cast_string="$("$LEMONDIR"/modules/block_screencast.sh)"; }
weather()      { weather_string="$("$LEMONDIR"/modules/block_weather.sh)"; }

# DESC: Initialize signals, print lemonbar strings
# ARGS: $1 (required): Message to print (defaults to a green foreground)
#       $2 (optional): Colour to print the message with. This can be an ANSI
#                      escape code or one of the prepopulated colour variables.
#       $3 (optional): Set to any value to not append a new line to the message
# OUTS: None
sig_init() {
    trap 'wsindicator'          RTMIN+2
    trap 'cpu'                  RTMIN+3
    trap 'clock'                RTMIN+4
    trap 'window_title'         RTMIN+5
    trap 'volume "$pid"'        RTMIN+6
    trap 'monitor "+" "$pid"'   RTMIN+7
    trap 'monitor "-" "$pid"'   RTMIN+8
    trap 'tray'                 RTMIN+9
    trap 'network'              RTMIN+10
    trap 'battery'              RTMIN+10
    trap 'screencast'           RTMIN+11
    trap 'weather'              RTMIN+12

    # own PID
    pid="$BASHPID"

    "$LEMONDIR"/scheduler.sh "$pid" &
    scheduler_pid="$!"

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

main () {
    sig_init
    while true; do
        render_line
        sleep infinity &
        # true neccessary here as every signal from scheduler would terminate sighandler
        wait $! || true
    done
}

main
