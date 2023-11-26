#!/bin/bash

source "$HOME/.config/bspwm/lemonbar/config.sh"
max_length=45

cleanup() {
    if [[ -e "$title_fifo" ]]; then
        rm "$title_fifo"
    fi
    # Disable the termination trap handler to prevent potential recursion
    trap - TERM
    kill 0
}

# trap 0 -> hook for closing/terminating shell
trap 'cleanup' INT TERM QUIT EXIT 0

# create named pipe
title_fifo="${tmp_Dir}/lemonbar_title.fifo"
if [[ -e "$title_fifo" ]]; then
    rm "$title_fifo"
fi
mkfifo "$title_fifo"

activeWindow() {
    # endless loop, for xtmon see https://github.com/vimist/xtmon/tree/master
    xtmon | while read -r line; do
        sleep 0.1
        if [[ $line =~ ^([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]*(.*) ]]; then
            focus_title="${BASH_REMATCH[1]}"
            window_title="${BASH_REMATCH[3]}"
            if [[ "$focus_title" == "focus_changed" || "$focus_title" == "title_changed" ]]; then
                pkill -RTMIN+5 sighandler.sh
                if [[ -z "$window_title" ]]; then
                    window_title="Desktop"
                fi
                if [ ${#window_title} -gt $max_length ]; then
                    limited_title="${window_title:0:$max_length}"
                else
                    limited_title="$window_title"
                fi
                printf "%s\n" "%{B$COLOR_DEFAULT_BG}%{F$COLOR_FREE_FG}%{+u}$PADDING$limited_title$PADDING%{-u}%{F-}%{B-}" > "$title_fifo"
            fi
        fi
    done
}

activeWindow
