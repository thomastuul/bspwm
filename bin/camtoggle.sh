#!/usr/bin/env bash
# Toggle a small preview window for the preferred visible-light camera.

set -o nounset

readonly RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
readonly PID_FILE="$RUNTIME_DIR/bspwm-camera-preview-${UID}.pid"
readonly LOCK_FILE="$RUNTIME_DIR/bspwm-camera-preview-${UID}.lock"
readonly WINDOW_TITLE="bspwm-camera-preview"
readonly DEFAULT_PREFERRED_CAMERA="Poly"

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
    local attempt node preferred
    preferred=${CAMERA_PREVIEW_PREFERRED:-$DEFAULT_PREFERRED_CAMERA}

    for ((attempt = 0; attempt < 20; attempt++)); do
        if node=$(find_camera "$preferred" || find_camera ""); then
            printf '%s\n' "$node"
            return 0
        fi
        sleep 0.1
    done
    return 1
}

is_preview_process() {
    local pid=$1 cmdline

    [[ $pid =~ ^[1-9][0-9]*$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    [[ -r /proc/$pid/comm && $(<"/proc/$pid/comm") == mpv ]] || return 1
    [[ -r /proc/$pid/cmdline ]] || return 1

    cmdline=$(tr '\0' ' ' <"/proc/$pid/cmdline") || return 1
    [[ $cmdline == *"--title=$WINDOW_TITLE"* && $cmdline == *"av://v4l2:"* ]]
}

stop_preview() {
    local pid

    [[ -r $PID_FILE ]] || return 1
    read -r pid <"$PID_FILE" || return 1
    is_preview_process "$pid" || return 1
    kill "$pid"
}

cleanup_stale_pid_file() {
    local pid

    [[ -r $PID_FILE ]] || return 0
    read -r pid <"$PID_FILE" || {
        rm -f -- "$PID_FILE"
        return 0
    }
    is_preview_process "$pid" || rm -f -- "$PID_FILE"
}

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

if stop_preview; then
    rm -f -- "$PID_FILE"
    exit 0
fi
cleanup_stale_pid_file

command -v mpv >/dev/null 2>&1 || exit 0
node=$(wait_for_camera) || exit 0

mpv \
    --title="$WINDOW_TITLE" \
    --geometry=-0-0 \
    --autofit=20% \
    --profile=low-latency \
    --no-audio \
    "av://v4l2:${node}" &
mpv_pid=$!
printf '%s\n' "$mpv_pid" >"$PID_FILE"

# Keep the lock only for the start/stop critical section.  If the starter kept
# it while waiting for mpv to exit, a second hotkey invocation could not acquire
# the lock and therefore could not toggle the preview off.
flock -u 9

wait "$mpv_pid"
status=$?

if [[ -r $PID_FILE && $(<"$PID_FILE") == "$mpv_pid" ]]; then
    rm -f -- "$PID_FILE"
fi
exit "$status"
