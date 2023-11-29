#!/usr/bin/env bash

#set -x

set -o errexit      # Exit on most errors (see the manual)
set -o nounset      # Disallow expansion of unset variables
set -o pipefail     # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
set -o errtrace     # Ensure the error trap handler is inherited

source "$LEMONDIR/config.sh"

connection=$(xrandr --listmonitors | awk 'NR==2 {print $4}')

brightness=$(xrandr --verbose | grep -i "$connection" -A10 | grep -i Brightness | cut -f2 -d ' ' | head -n1)

brightness_int=$(echo "$brightness * 100" | bc | cut -f1 -d '.')

inc_brightness() {
    new_brightness_int=$((brightness_int + 5))
    if [ "$new_brightness_int" -gt 100 ]; then
        new_brightness_int=100
    fi
    new_brightness=$(echo "$new_brightness_int / 100" | bc -l)
    xrandr --output "$connection" --brightness "$new_brightness"
}

dec_brightness() {
    new_brightness_int=$((brightness_int - 5))
    if [ "$new_brightness_int" -lt 0 ]; then
        new_brightness_int=0
    fi
    new_brightness=$(echo "$new_brightness_int / 100" | bc -l)
    xrandr --output "$connection" --brightness "$new_brightness"
}

monitor() {
    icon=""

    mon_string="%{B$COLOR_DEFAULT_BG}%{F$COLOR_MONITOR_FG}%{+u} $icon $brightness_int% %{-u}%{F-}%{B-}"

    printf "%s" "$mon_string"
}

inc="pkill -RTMIN+7 sighandler.sh"
dec="pkill -RTMIN+8 sighandler.sh"

if [[ "$1" == "+" ]]; then
    inc_brightness
elif [[ "$1" == "-" ]]; then
    dec_brightness
else
    :
fi

printf "%s" "%{A4:${inc}:}%{A5:${dec}:}$(monitor)%{A}%{A}"
