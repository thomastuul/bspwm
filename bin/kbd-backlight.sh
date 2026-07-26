#!/usr/bin/env bash

set -u

command -v busctl >/dev/null 2>&1 || exit 1

shopt -s nullglob
devices=(/sys/class/leds/*kbd_backlight*)

# Desktop systems commonly have no kernel-supported keyboard backlight.
((${#devices[@]} > 0)) || exit 0

device=${devices[0]##*/}
brightness_file=${devices[0]}/brightness
maximum_file=${devices[0]}/max_brightness

read -r current <"$brightness_file" || exit 1
read -r maximum <"$maximum_file" || exit 1

[[ "$current" =~ ^[0-9]+$ && "$maximum" =~ ^[1-9][0-9]*$ ]] || exit 1

step=$(((maximum + 9) / 10))

case "${1:-}" in
    up)
        target=$((current + step))
        ((target > maximum)) && target=$maximum
        ;;
    down)
        target=$((current - step))
        ((target < 0)) && target=0
        ;;
    toggle)
        if ((current == 0)); then
            target=$(((maximum + 1) / 2))
        else
            target=0
        fi
        ;;
    *)
        printf 'Usage: %s {up|down|toggle}\n' "${0##*/}" >&2
        exit 2
        ;;
esac

busctl --system call \
    org.freedesktop.login1 \
    /org/freedesktop/login1/session/auto \
    org.freedesktop.login1.Session \
    SetBrightness ssu leds "$device" "$target" >/dev/null
