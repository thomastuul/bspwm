#!/usr/bin/env bash

source "$HOME/.config/bspwm/lemonbar/config.sh"

trayer --edge top --align right --SetDockType true \
 --SetPartialStrut true --expand true --transparent true \
 --alpha 1 --tint $COLOR_DEFAULT_BG --widthtype request  \
 --width 3 --height $PANEL_HEIGHT --distancefrom right --distance 35


