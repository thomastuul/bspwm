#!/usr/bin/env bash
# xtmon.sh — Continuous output of the active X11 window title
# Events: focus changes and title changes (tab switches in the browser)
# If no active window: print "Desktop"
# Dependency: xprop (xorg-xprop)
# Exit with Ctrl-C

set -o errexit -o nounset -o pipefail
export LC_ALL=C.UTF-8

if ! declare -F log_error >/dev/null; then
    printf 'logging bootstrap not loaded: %s\n' "${BASH_ENV:-unset}" >&2
    exit 1
fi

err() { printf '%s\n' "xtmon: $*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

get_active_wid() {
    # _NET_ACTIVE_WINDOW(WINDOW): window id # 0x04000007
    xprop -root _NET_ACTIVE_WINDOW 2>/dev/null |
        awk -F'#' 'NR==1{gsub(/[[:space:]]/, "", $2); print $2}'
}

read_title_once() {
    # $1 = WID
    local wid=$1 out
    out="$(xprop -id "$wid" _NET_WM_NAME 2>/dev/null | awk -F'"' 'NF>=2{print $2; exit}')" || true
    if [ -z "${out:-}" ]; then
        out="$(xprop -id "$wid" WM_NAME 2>/dev/null | awk -F'"' 'NF>=2{print $2; exit}')" || true
    fi
    [ -n "${out:-}" ] && printf '%s\n' "$out"
}

TITLE_WATCHER_PID=""
ROOT_WATCHER_PID=""
LAST_TITLE=""

print_desktop_if_needed() {
    if [ "${LAST_TITLE:-}" != "Desktop" ]; then
        printf '%s\n' "Desktop"
        LAST_TITLE="Desktop"
    fi
}

watch_title_changes() {
    # $1 = WID
    local wid=$1 line title last_title
    local source_pid="" source_fd=""

    cleanup_title_source() {
        trap - INT TERM HUP
        if [[ $source_pid =~ ^[0-9]+$ ]]; then
            kill -TERM "$source_pid" 2>/dev/null || true
            wait "$source_pid" 2>/dev/null || true
        fi
    }
    trap 'cleanup_title_source; exit 0' INT TERM HUP

    coproc TITLE_EVENTS {
        exec xprop -spy -id "$wid" _NET_WM_NAME WM_NAME 2>/dev/null
    }
    source_pid=$TITLE_EVENTS_PID
    source_fd=${TITLE_EVENTS[0]}
    last_title="${LAST_TITLE:-}"

    while IFS= read -r line <&"$source_fd"; do
        title="$(printf '%s' "$line" | awk -F'"' 'NF>=2{print $2}')"
        if [[ -n "${title:-}" && "$title" != "$last_title" ]]; then
            printf '%s\n' "$title"
            last_title=$title
        fi
    done

    cleanup_title_source
}

start_title_watcher() {
    # $1 = WID
    local wid=$1 title

    # Print the initial title immediately when available.
    title="$(read_title_once "$wid")" || true
    if [[ -n "${title:-}" && "$title" != "${LAST_TITLE:-}" ]]; then
        printf '%s\n' "$title"
        LAST_TITLE=$title
    fi

    watch_title_changes "$wid" &
    TITLE_WATCHER_PID=$!
}

stop_title_watcher() {
    if [[ -n "${TITLE_WATCHER_PID:-}" ]]; then
        kill "$TITLE_WATCHER_PID" 2>/dev/null || true
        wait "$TITLE_WATCHER_PID" 2>/dev/null || true
    fi

    TITLE_WATCHER_PID=""
    # Keep LAST_TITLE so duplicate titles remain suppressed.
}

cleanup() {
    trap - EXIT INT TERM HUP
    stop_title_watcher

    if [[ $ROOT_WATCHER_PID =~ ^[0-9]+$ ]]; then
        kill -TERM "$ROOT_WATCHER_PID" 2>/dev/null || true
        wait "$ROOT_WATCHER_PID" 2>/dev/null || true
    fi
    ROOT_WATCHER_PID=""
}

if ! have xprop; then
    err "xprop nicht gefunden (xorg-xprop installieren)."
    exit 1
fi

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 0' HUP

current_wid="$(get_active_wid || true)"
if [ -z "${current_wid:-}" ] || [ "${current_wid}" = "0x0" ]; then
    # Print "Desktop" once when no window is active.
    print_desktop_if_needed
else
    start_title_watcher "$current_wid"
fi

# Watch active-window changes. The root watcher is an explicit coprocess so
# cleanup can stop and reap it reliably.
coproc ROOT_EVENTS {
    exec xprop -spy -root _NET_ACTIVE_WINDOW 2>/dev/null
}
ROOT_WATCHER_PID=$ROOT_EVENTS_PID
root_watcher_fd=${ROOT_EVENTS[0]}

while IFS= read -r root_line; do
    new_wid="$(printf '%s' "$root_line" | awk -F'#' 'NR==1{gsub(/[[:space:]]/, "", $2); print $2}')"

    if [ -z "${new_wid:-}" ] || [ "${new_wid}" = "0x0" ]; then
        # The desktop has focus, so no active window exists.
        stop_title_watcher
        current_wid=""
        print_desktop_if_needed
        continue
    fi

    if [ "${new_wid}" != "${current_wid:-}" ]; then
        stop_title_watcher
        current_wid="$new_wid"
        start_title_watcher "$current_wid"
    fi
done <&"$root_watcher_fd"

wait "$ROOT_WATCHER_PID" 2>/dev/null || true
ROOT_WATCHER_PID=""
