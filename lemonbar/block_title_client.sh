#!/usr/bin/env bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

title_fifo="${tmp_dir}/lemonbar_title.fifo"

# wait for fifo file to be established
if [[ ! -p "$title_fifo" ]]; then
    printf "none"
else
    read -t 0.1 -r line < "$title_fifo"
    printf "%s" "$line"
fi

# vim: syntax=bash
