#!/usr/bin/bash

# Hint: Shebang has to be here as it is!
# don't change it to '/usr/bin/env bash'

cleanup() {
    if ps -q "${scheduler_pid}" > /dev/null; then
        kill -KILL "${scheduler_pid}"
    fi
    trap - TERM
    kill 0
}

trap cleanup INT TERM QUIT EXIT 0

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
    tmp_Dir="$tmp_Dir" title_string="$("$LEMONDIR"/block_title_client.sh)"
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

trap 'wsindicator'      RTMIN+2
trap 'cpu'              RTMIN+3
trap 'clock'            RTMIN+4
trap 'window_title'     RTMIN+5
trap 'volume'           RTMIN+6
trap 'monitor "+"'      RTMIN+7
trap 'monitor "-"'      RTMIN+8
trap 'tray'             RTMIN+9
trap 'network'          RTMIN+10

"$LEMONDIR"/scheduler.sh &
scheduler_pid=$!

# init
#window_title -> don't initialize it, its updated at an initial signal
wsindicator
cpu
clock
launcher
power
volume
monitor
tray
network

while true; do
    printf "%s" "%{l}${launch_string}${ws_string}%{c}${title_string}%{r}${net_string}${mon_string}${vol_string}${cpu_string}${clock_string}${tray_string}${power_string}"
    wait $scheduler_pid
done
