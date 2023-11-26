#!/usr/bin/env bash

# vim: syntax=bash

source "$LEMONDIR/config.sh"

name=""
run="rofi -no-config -no-lazy-grab -show drun -modi drun -theme ~/.config/bspwm/rofi/launcher.rasi"

launcher="%{A:$run:}%{F$COLOR_DEFAULT_FG}%{B$COLOR_DEFAULT_BG} ${name}$PADDING%{B-}%{F-}%{A}"

printf "%s" "$launcher"
