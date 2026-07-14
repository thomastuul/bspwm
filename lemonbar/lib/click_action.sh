#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=../config.sh
source "$LEMONDIR/config.sh"

die() {
    printf 'click_action: %s\n' "$*" >&2
    exit 2
}

validate_signal_target() {
    local signal=$1 pid=$2

    [[ $signal =~ ^[0-9]+$ && $signal -ge 1 && $signal -le 64 ]] ||
        die "invalid signal: $signal"
    [[ $pid =~ ^[0-9]+$ ]] || die "invalid PID: $pid"
    kill -0 "$pid" 2>/dev/null || exit 0
}

send_signal() {
    local signal=$1 pid=$2

    validate_signal_target "$signal" "$pid"
    kill -s "$signal" "$pid" 2>/dev/null || true
}

open_terminal() {
    local program=$1

    case $program in
    btop | nmtui | pulsemixer) ;;
    *) die "unsupported terminal program: $program" ;;
    esac

    setsid -f "$TERMINAL" -e "$program" >/dev/null 2>&1
}

change_volume() {
    local action=$1 step=$2 signal=$3 pid=$4

    [[ $step =~ ^[1-9][0-9]*$ && $step -le 100 ]] ||
        die "invalid volume step: $step"
    validate_signal_target "$signal" "$pid"

    case $action in
    increase)
        if command -v pamixer >/dev/null 2>&1; then
            pamixer -i "$step"
        elif command -v pactl >/dev/null 2>&1; then
            pactl set-sink-volume @DEFAULT_SINK@ "+${step}%"
        else
            amixer set Master "${step}%+" >/dev/null
        fi
        ;;
    decrease)
        if command -v pamixer >/dev/null 2>&1; then
            pamixer -d "$step"
        elif command -v pactl >/dev/null 2>&1; then
            pactl set-sink-volume @DEFAULT_SINK@ "-${step}%"
        else
            amixer set Master "${step}%-" >/dev/null
        fi
        ;;
    toggle)
        if command -v pamixer >/dev/null 2>&1; then
            pamixer -t
        elif command -v pactl >/dev/null 2>&1; then
            pactl set-sink-mute @DEFAULT_SINK@ toggle
        else
            amixer set Master toggle >/dev/null
        fi
        ;;
    *) die "unsupported volume action: $action" ;;
    esac

    send_signal "$signal" "$pid"
}

case ${1:-} in
terminal)
    [[ $# -eq 2 ]] || die "terminal expects <program>"
    open_terminal "$2"
    ;;
signal)
    [[ $# -eq 3 ]] || die "signal expects <signal> <pid>"
    send_signal "$2" "$3"
    ;;
volume)
    [[ $# -eq 5 ]] || die "volume expects <action> <step> <signal> <pid>"
    change_volume "$2" "$3" "$4" "$5"
    ;;
workspace)
    [[ $# -eq 2 ]] || die "workspace expects <desktop>"
    bspc desktop -f "$2"
    ;;
notify)
    [[ $# -eq 3 ]] || die "notify expects <title> <message>"
    notify-send "$2" "$3"
    ;;
*) die "unsupported action: ${1:-missing}" ;;
esac
