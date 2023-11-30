#!/bin/bash

set -o errexit      # Exit on most errors (see the manual)
set -o nounset      # Disallow expansion of unset variables
set -o pipefail     # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
set -o errtrace     # Ensure the error trap handler is inherited

source "$HOME/.config/bspwm/lemonbar/config.sh"
max_length_title=45

cleanup() {
    if [[ -e "$title_fifo" ]]; then
        rm "$title_fifo"
    fi
    # Disable the termination trap handler to prevent potential recursion
    trap - TERM
    kill 0
}

# DESC:
# ARGS: None
# OUTS: None
script_trap_err() {
    local parent_lineno="$1"
    local code="$2"
    local commands="$3"
    echo "Error exit status $code, at file $0 on or near line $parent_lineno: $commands"
}

trap 'cleanup' INT TERM QUIT EXIT
trap 'script_trap_err "${LINENO}/${BASH_LINENO}" "$?" "$BASH_COMMAND"'  ERR

# create named pipe
title_fifo="${tmp_Dir}/lemonbar_title.fifo"
if [[ -e "$title_fifo" ]]; then
    rm "$title_fifo"
fi
mkfifo "$title_fifo"

activeWindow() {
    # endless loop, for xtmon see https://github.com/vimist/xtmon/tree/master
    xtmon | while read -r line; do
        sleep 0.05
        if [[ $line =~ ^([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]*(.*) ]]; then
            focus_title="${BASH_REMATCH[1]}"
            window_title="${BASH_REMATCH[3]}"
            if [[ "$focus_title" == "focus_changed" || "$focus_title" == "title_changed" || "$focus_title" == "initial_focus" ]]; then
                kill -RTMIN+5 "$sighandler_pid"
                if [[ -z "$window_title" ]]; then
                    window_title="Desktop"
                fi
                if [ ${#window_title} -gt $max_length_title ]; then
                    limited_title="${window_title:0:$max_length_title}"
                else
                    limited_title="$window_title"
                fi
                printf "%s\n" "%{B$COLOR_DEFAULT_BG}%{F$COLOR_FREE_FG}%{+u}$PADDING$limited_title$PADDING%{-u}%{F-}%{B-}" > "$title_fifo"
            fi
        fi
    done
}

activeWindow
