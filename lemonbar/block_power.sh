#!/usr/bin/env bash

# vim: syntax=bash

source "$LEMONDIR/config.sh"

name=""

#run="rofi -no-config -no-lazy-grab -show powermenu -modi powermenu:./.local/share/rofi/rofi-power-menu.sh -theme /home/thomas/.config/bspwm/rofi/powermenu.rasi"

run="$LEMONDIR/power_rofi.sh"

power="%{A:${run}:}%{F$COLOR_DEFAULT_FG}%{B$COLOR_DEFAULT_BG}$PADDING${name}$PADDING%{B-}%{F-}%{A}"

printf "%s" "$power"
