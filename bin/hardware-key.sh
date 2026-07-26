#!/usr/bin/env bash
# Handle common laptop and desktop hardware keys with automatic backend
# detection. Unsupported actions are intentionally silent.

set -o nounset

readonly AUDIO_STEP=2
readonly BRIGHTNESS_STEP=5
readonly BRIGHTNESS_MIN=5
readonly KBD_BRIGHTNESS_STEP=10

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

sliverbar_action() {
    local executable

    if command_exists sliverbar; then
        executable=$(command -v sliverbar)
    elif [[ -x $HOME/.local/bin/sliverbar ]]; then
        executable=$HOME/.local/bin/sliverbar
    else
        return 1
    fi
    "$executable" --action "$@" >/dev/null 2>&1
}

audio_sink() {
    local operation=$1 sliverbar_operation=$1

    if [[ $sliverbar_operation == mute ]]; then
        sliverbar_operation=toggle
    fi
    sliverbar_action volume "$sliverbar_operation" && return 0
    if command_exists wpctl; then
        case $operation in
            up)
                wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ "${AUDIO_STEP}%+"
                ;;
            down)
                wpctl set-volume @DEFAULT_AUDIO_SINK@ "${AUDIO_STEP}%-"
                ;;
            mute)
                wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
                ;;
        esac
    elif command_exists pactl; then
        case $operation in
            up)
                pactl set-sink-volume @DEFAULT_SINK@ "+${AUDIO_STEP}%"
                ;;
            down)
                pactl set-sink-volume @DEFAULT_SINK@ "-${AUDIO_STEP}%"
                ;;
            mute)
                pactl set-sink-mute @DEFAULT_SINK@ toggle
                ;;
        esac
    elif command_exists amixer; then
        case $operation in
            up)
                amixer set Master "${AUDIO_STEP}%+" >/dev/null
                ;;
            down)
                amixer set Master "${AUDIO_STEP}%-" >/dev/null
                ;;
            mute)
                amixer set Master toggle >/dev/null
                ;;
        esac
    fi
}

audio_source_mute() {
    if command_exists wpctl; then
        wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
    elif command_exists pactl; then
        pactl set-source-mute @DEFAULT_SOURCE@ toggle
    elif command_exists amixer; then
        amixer set Capture toggle >/dev/null
    fi
}

find_brightness_device() {
    local device

    shopt -s nullglob
    for device in /sys/class/backlight/*; do
        [[ -r $device/brightness && -r $device/max_brightness ]] || continue
        printf '%s\n' "$device"
        return 0
    done
    return 1
}

set_logind_brightness() {
    local subsystem=$1 device=$2 target=$3

    command_exists busctl || return 0
    busctl --system call \
        org.freedesktop.login1 \
        /org/freedesktop/login1/session/auto \
        org.freedesktop.login1.Session \
        SetBrightness ssu "$subsystem" "${device##*/}" "$target" >/dev/null
}

display_brightness() {
    local direction=$1 device current maximum current_percent target_percent target

    sliverbar_action brightness "$direction" && return 0
    device=$(find_brightness_device) || return 0
    read -r current <"$device/brightness" || return 0
    read -r maximum <"$device/max_brightness" || return 0
    [[ $current =~ ^[0-9]+$ && $maximum =~ ^[1-9][0-9]*$ ]] || return 0

    current_percent=$(((current * 100 + maximum / 2) / maximum))
    if [[ $direction == up ]]; then
        target_percent=$((current_percent + BRIGHTNESS_STEP))
        ((target_percent > 100)) && target_percent=100
    else
        target_percent=$((current_percent - BRIGHTNESS_STEP))
        ((target_percent < BRIGHTNESS_MIN)) && target_percent=$BRIGHTNESS_MIN
    fi
    target=$(((target_percent * maximum + 50) / 100))
    set_logind_brightness backlight "$device" "$target"
}

find_keyboard_backlight() {
    local device

    shopt -s nullglob
    for device in /sys/class/leds/*kbd_backlight*; do
        [[ -r $device/brightness && -r $device/max_brightness ]] || continue
        printf '%s\n' "$device"
        return 0
    done
    return 1
}

keyboard_brightness() {
    local operation=$1 device current maximum step target

    device=$(find_keyboard_backlight) || return 0
    read -r current <"$device/brightness" || return 0
    read -r maximum <"$device/max_brightness" || return 0
    [[ $current =~ ^[0-9]+$ && $maximum =~ ^[1-9][0-9]*$ ]] || return 0
    step=$(((maximum * KBD_BRIGHTNESS_STEP + 99) / 100))

    case $operation in
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
    esac
    set_logind_brightness leds "$device" "$target"
}

bluetooth_power() {
    local state=$1

    command_exists bluetoothctl || return 0
    bluetoothctl power "$state" >/dev/null 2>&1 || true
}

airplane_toggle() {
    local wifi_state

    command_exists nmcli || return 0
    wifi_state=$(nmcli -terse -fields WIFI radio 2>/dev/null) || return 0
    if [[ $wifi_state == enabled ]]; then
        nmcli radio all off
        bluetooth_power off
    else
        nmcli radio all on
        bluetooth_power on
    fi
}

wifi_toggle() {
    local wifi_state

    command_exists nmcli || return 0
    wifi_state=$(nmcli -terse -fields WIFI radio 2>/dev/null) || return 0
    if [[ $wifi_state == enabled ]]; then
        nmcli radio wifi off
    else
        nmcli radio wifi on
    fi
}

bluetooth_toggle() {
    local state

    command_exists bluetoothctl || return 0
    state=$(bluetoothctl show 2>/dev/null |
        awk '$1 == "Powered:" { print $2; exit }')
    if [[ $state == yes ]]; then
        bluetooth_power off
    else
        bluetooth_power on
    fi
}

media_control() {
    command_exists playerctl || return 0
    playerctl "$1"
}

touchpad_toggle() {
    local schema=org.gnome.desktop.peripherals.touchpad state

    command_exists gsettings || return 0
    state=$(gsettings get "$schema" send-events 2>/dev/null) || return 0
    if [[ $state == "'enabled'" ]]; then
        gsettings set "$schema" send-events disabled
    else
        gsettings set "$schema" send-events enabled
    fi
}

display_off() {
    command_exists xset || return 0
    sleep 0.5
    xset dpms force off
}

display_toggle() {
    if command_exists autorandr; then
        autorandr --cycle
    elif command_exists xrandr; then
        xrandr --auto
    fi
}

suspend_system() {
    command_exists systemctl || return 0
    systemctl suspend
}

case ${1:-} in
    volume-up)
        audio_sink up
        ;;
    volume-down)
        audio_sink down
        ;;
    volume-mute)
        audio_sink mute
        ;;
    microphone-mute)
        audio_source_mute
        ;;
    brightness-up)
        display_brightness up
        ;;
    brightness-down)
        display_brightness down
        ;;
    keyboard-brightness-up)
        keyboard_brightness up
        ;;
    keyboard-brightness-down)
        keyboard_brightness down
        ;;
    keyboard-brightness-toggle)
        keyboard_brightness toggle
        ;;
    airplane-toggle)
        airplane_toggle
        ;;
    wifi-toggle)
        wifi_toggle
        ;;
    bluetooth-toggle)
        bluetooth_toggle
        ;;
    media-play-pause)
        media_control play-pause
        ;;
    media-next)
        media_control next
        ;;
    media-previous)
        media_control previous
        ;;
    media-stop)
        media_control stop
        ;;
    touchpad-toggle)
        touchpad_toggle
        ;;
    display-off)
        display_off
        ;;
    display-toggle)
        display_toggle
        ;;
    suspend)
        suspend_system
        ;;
    *)
        printf 'Usage: %s ACTION\n' "${0##*/}" >&2
        exit 2
        ;;
esac
