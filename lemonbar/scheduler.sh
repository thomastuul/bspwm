#!/usr/bin/env bash

dummy() {
    printf ""
}

seconds=0

while true; do
    # every second
    pkill -RTMIN+3 sighandler.sh
    pkill -RTMIN+4 sighandler.sh

    # every 5 seconds
    if [[ $((seconds % 5)) -eq 0 ]]; then
        dummy
    fi

    # every 10 seconds
    if [[ $((seconds % 10)) -eq 0 ]]; then
        dummy
    fi

    # every 60 seconds
    if [[ $((seconds % 60)) -eq 0 ]]; then
        pkill -RTMIN+10 sighandler.sh
    fi

    ((seconds++))
    sleep 1
done
