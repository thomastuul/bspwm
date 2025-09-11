#!/bin/bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

set -o errexit      # Exit on most errors (see the manual)
set -o nounset      # Disallow expansion of unset variables
set -o pipefail     # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
set -o errtrace     # Ensure the error trap handler is inherited

source "$LEMONDIR/config.sh"

# DESC: Remove FIFO
# ARGS: None
# OUTS: None
trap_cleanup() {
    # Disable the termination trap handler to prevent potential recursion
    trap - TERM
    if [[ -e "$title_fifo" ]]; then
        rm "$title_fifo"
    fi
}

# DESC: Errorhandler
# ARGS: $1: If only param -> Exit status code
#           else line number of err occurence.
#       $2: Exit status code
#       $3: invoked command
# OUTS: None
trap_err() {
    local parent_lineno="$1"
    local code="$2"
    if [[ ${2:-} -eq 143 ]]; then return 0; fi # xtmon.sh ends with 143 at stop
    local commands="$3"
    echo "Error exit status $code, at file $0 on or near line $parent_lineno: $commands"
}

trap 'trap_cleanup' INT TERM QUIT EXIT
trap 'trap_err "${LINENO}/${BASH_LINENO}" "$?" "$BASH_COMMAND"'  ERR

# create named pipe
# shellcheck disable=SC2154
title_fifo="${tmp_dir}/lemonbar_title.fifo"
if [[ -e "$title_fifo" ]]; then
    rm "$title_fifo"
fi
mkfifo "$title_fifo"

# DESC: Get title of active window
# ARGS: None
# OUTS: None
activeWindow() {
    # endless loop, for original xtmon see https://github.com/vimist/xtmon/tree/master
    # I'm using my selfmade clone in bash
    "$LEMONDIR/xtmon.sh" | while read -r line; do
        sleep 0.05
        truncated=$(echo "$line" | awk -v m="$TITLE_MAX_LENGHT" '{print substr($0,1,m)}')
        # shellcheck disable=SC2154
        kill -RTMIN+5 "$sighandler_pid"
        printf "%s\n" "%{B$COLOR_DEFAULT_BG}%{F$COLOR_FREE_FG}%{+u}$PADDING$truncated$PADDING%{-u}%{F-}%{B-}" > "$title_fifo"
    done
}

activeWindow
