#!/usr/bin/bash

#set -x

# Hint: Shebang has to be here as it is!
# don't change it to '/usr/bin/env bash'

#set -o errexit      # Exit on most errors (see the manual)
#set -o nounset      # Disallow expansion of unset variables
#set -o pipefail     # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
#set -o errtrace     # Ensure the error trap handler is inherited

cleanup() {
    if ps -q "${scheduler_pid}" > /dev/null; then
        kill -KILL "${scheduler_pid}"
    fi
    trap - TERM
    kill 0
}

# DESC:
# ARGS: None
# OUTS: None
script_trap_err() {
    local parent_lineno="$1"
    local code="$2"
    local commands="$3"
    echo "Error exit status $code, at file $0 on or near line $parent_lineno: $commands"
}

trap cleanup INT TERM QUIT EXIT
trap 'script_trap_err "${LINENO}/${BASH_LINENO}" "$?" "$BASH_COMMAND"'  ERR

cpu() {
    cpu_string="$("$LEMONDIR"/block_cpu.sh)"
}

clock() {
    clock_string="$("$LEMONDIR"/block_clock.sh)"
}

wsindicator() {
    ws_string="$("$LEMONDIR"/block_wsindicator.sh)"
}

window_title() {
    title_string="$("$LEMONDIR"/block_title_client.sh "$tmp_dir")"
}

launcher() {
    launch_string="$("$LEMONDIR"/block_launcher.sh)"
}

power() {
    power_string="$("$LEMONDIR"/block_power.sh)"
}

volume() {
    vol_string="$("$LEMONDIR"/block_volume.sh)"
}

monitor() {
    mon_string="$("$LEMONDIR"/block_brightness.sh "$1")"
}

tray() {
    tray_string="$("$LEMONDIR"/block_trayer.sh)"
}

network() {
    net_string="$("$LEMONDIR"/block_network.sh)"
}

# DESC: Initialize signals, print lemonbar strings
# ARGS: $1 (required): Message to print (defaults to a green foreground)
#       $2 (optional): Colour to print the message with. This can be an ANSI
#                      escape code or one of the prepopulated colour variables.
#       $3 (optional): Set to any value to not append a new line to the message
# OUTS: None
sig_init() {
    trap 'wsindicator'      RTMIN+2
    trap 'cpu'              RTMIN+3
    trap 'clock'            RTMIN+4
    trap 'window_title'     RTMIN+5
    trap 'volume'           RTMIN+6
    trap 'monitor "+"'      RTMIN+7
    trap 'monitor "-"'      RTMIN+8
    trap 'tray'             RTMIN+9
    trap 'network'          RTMIN+10

    if [[ $# -lt 2 ]]; then
        script_exit 'Missing required argument to sig_init()!' 2
    fi

    tmp_dir=$1
    lemondir=$2

    "$lemondir"/scheduler.sh &
    scheduler_pid=$!

    # init
    #window_title -> don't initialize it, its updated at an initial signal
    wsindicator
    cpu
    clock
    launcher
    power
    volume
    monitor "x"
    tray
    network

    while true; do
        printf "%s" "%{l}${launch_string}${ws_string}%{c}${title_string}%{r}${net_string}${mon_string}${vol_string}${cpu_string}${clock_string}${tray_string}${power_string}"
        wait $scheduler_pid
    done
}

sig_init "$@"
