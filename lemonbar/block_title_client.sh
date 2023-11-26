#!/usr/bin/env bash

# vim: syntax=bash

title_fifo="${tmp_Dir}/lemonbar_title.fifo"

# wait for fifo file to be established
if [[ ! -p "$title_fifo" ]]; then
    printf "none"
else
    read -t 0.1 -r line < "$title_fifo"
    printf "%s" "$line"
fi
