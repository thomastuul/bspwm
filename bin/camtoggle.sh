#!/usr/bin/env bash
# Toggle a small preview window for the preferred visible-light camera.

set -o nounset

readonly PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/bspwm-camera-preview-${UID}.pid"

find_camera() {
    local preferred=$1 device name index

    for device in /sys/class/video4linux/video*; do
        [[ -r $device/name && -r $device/index ]] || continue
        read -r name <"$device/name" || continue
        read -r index <"$device/index" || continue
        [[ $index == 0 && $name != *IR* ]] || continue
        [[ -z $preferred || $name == *"$preferred"* ]] || continue
        [[ -e /dev/${device##*/} ]] || continue
        printf '/dev/%s\n' "${device##*/}"
        return 0
    done
    return 1
}

wait_for_camera() {
    local attempt node

    for ((attempt = 0; attempt < 20; attempt++)); do
        if node=$(find_camera Poly || find_camera ""); then
            printf '%s\n' "$node"
            return 0
        fi
        sleep 0.1
    done
    return 1
}

stop_preview() {
    local pid

    [[ -r $PID_FILE ]] || return 1
    read -r pid <"$PID_FILE" || return 1
    [[ $pid =~ ^[1-9][0-9]*$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    [[ -r /proc/$pid/comm ]] || return 1
    [[ $(<"/proc/$pid/comm") == mpv ]] || return 1
    kill "$pid"
}

if stop_preview; then
    exit 0
fi
rm -f -- "$PID_FILE"

command -v mpv >/dev/null 2>&1 || exit 0
node=$(wait_for_camera) || exit 0

mpv \
    --title=bspwm-camera-preview \
    --geometry=-0-0 \
    --autofit=20% \
    --profile=low-latency \
    --no-audio \
    "av://v4l2:${node}" &
mpv_pid=$!
printf '%s\n' "$mpv_pid" >"$PID_FILE"
wait "$mpv_pid"
status=$?

if [[ $(<"$PID_FILE") == "$mpv_pid" ]]; then
    rm -f -- "$PID_FILE"
fi
exit "$status"
