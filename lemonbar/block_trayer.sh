#!/usr/bin/env bash

# vim: syntax=bash

source "$LEMONDIR/config.sh"

trayer_width() {
    # Width of the trayer window
    width=$(xprop -name panel | grep 'program specified minimum size' | cut -d ' ' -f 5)
    # number of spaces
    num=$(( (width / 22) + 5  ))

    printf "%*s" $num ""
}

trayer="%{F$COLOR_DEFAULT_FG}%{B$COLOR_DEFAULT_BG}$(trayer_width)%{B-}%{F-}"

printf "%s" "$trayer"
