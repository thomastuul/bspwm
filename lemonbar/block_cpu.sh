#!/usr/bin/env bash

source "$LEMONDIR/config.sh"

icon=""
load=$(cut -d ' ' -f1 /proc/loadavg)

printf "%s" "%{A:/usr/bin/alacritty -e sh -c btop:}%{B$COLOR_DEFAULT_BG}%{F$COLOR_SYS_FG}%{+u} $icon ${load} %{-u}%{F-}%{B-}%{A}"
