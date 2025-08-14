#!/usr/bin/env bash

source "$HOME/.config/bspwm/lemonbar/config.sh"

color="$Background"
color="0x${color#\#}"

trayer --edge top --align right --SetDockType true \
 --SetPartialStrut true --expand true --transparent true \
 --alpha 1.0 --tint $color --widthtype request  \
 --width 3 --height $PANEL_HEIGHT --distancefrom right --distance 35


