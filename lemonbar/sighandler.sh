#!/bin/bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

# Hint: Shebang has to be here as it is!
# don't change it to '/usr/bin/env bash'

set -o errexit      # Exit on most errors (see the manual)
set -o nounset      # Disallow expansion of unset variables
set -o pipefail     # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
#set -o errtrace     # Ensure the error trap handler is inherited

trap_cleanup() {
    echo "PID: $!"
    echo "BASHPID: $BASHPID"
    trap - TERM
    kill "$scheduler_pid"
    wait
    kill "$BASHPID"
    wait
}

# DESC:
# ARGS: None
# OUTS: None
trap_err() {
    local parent_lineno="$1"
    local code="$2"
    local commands="$3"
    echo "Error exit status $code, at file $0 on or near line $parent_lineno: $commands"
}

trap trap_cleanup INT TERM QUIT EXIT HUP
trap 'trap_err "${LINENO}/${BASH_LINENO}" "$?" "$BASH_COMMAND"'  ERR

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
    tmp_dir="$tmp_dir" title_string="$("$LEMONDIR"/block_title_client.sh)"
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
    trap 'wsindicator'  RTMIN+2
    trap 'cpu'          RTMIN+3
    trap 'clock'        RTMIN+4
    trap 'window_title' RTMIN+5
    trap 'volume'       RTMIN+6
    trap 'monitor "+"'  RTMIN+7
    trap 'monitor "-"'  RTMIN+8
    trap 'tray'         RTMIN+9
    trap 'network'      RTMIN+10

    "$LEMONDIR"/scheduler.sh &
    scheduler_pid=$!

    # init
    window_title
    wsindicator
    cpu
    clock
    launcher
    power
    volume
    monitor ""
    tray
    network

    # disable termination at error as every signal from scheduler would terminate sighandler
    set +o errexit
    while true; do
        printf "%s" "%{l}${launch_string}${ws_string}%{c}${title_string}%{r}${net_string}${mon_string}${vol_string}${cpu_string}${clock_string}${tray_string}${power_string}"
        wait $scheduler_pid
    done
    set -o errexit
}

sig_init
