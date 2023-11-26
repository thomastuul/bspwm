#!/usr/bin/env bash

source "$LEMONDIR/config.sh"

Date() {
    date=$(date "+%a %b %d")
    printf "%s" "$date"
}

Time() {
    time=$(date "+%T")
    printf "%s" "$time"
}

printf "%s\n" "%{B$COLOR_DEFAULT_BG}%{F$COLOR_CLOCK_FG}%{+u}  $(Date)  $(Time) %{-u}%{F-}%{B-}"
