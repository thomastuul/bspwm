#!/usr/bin/env bash

# vim: syntax=bash

source "$LEMONDIR/config.sh"

trayer_width() {
    # Width of the trayer window
    width=1
    if [[ -n "$(pidof trayer)" ]]; then
        width=$(xprop -name panel | grep 'program specified minimum size' | cut -d ' ' -f 5)
        # number of spaces
        num=$(( (width / 16) + 3 ))
    fi

    printf "%*s" $num ""
}

trayer="%{F$COLOR_DEFAULT_FG}%{B$COLOR_DEFAULT_BG}$(trayer_width)%{B-}%{F-}"

printf "%s" "$trayer"
