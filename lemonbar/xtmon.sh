#!/usr/bin/env bash
# xtmon.sh — Continuous output of the active X11 window title
# Events: focus changes and title changes (tab switches in the browser)
# If no active window: print "Desktop"
# Dependency: xprop (xorg-xprop)
# Exit with Ctrl-C

set -o errexit -o nounset -o pipefail
export LC_ALL=C

err() { printf '%s\n' "xtmon: $*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

get_active_wid() {
    # _NET_ACTIVE_WINDOW(WINDOW): window id # 0x04000007
    xprop -root _NET_ACTIVE_WINDOW 2>/dev/null \
        | awk -F'#' 'NR==1{gsub(/[[:space:]]/, "", $2); print $2}'
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
LAST_TITLE=""

print_desktop_if_needed() {
    if [ "$1" = "0x0" ]; then
        # No active window
        printf '%s\n' "Desktop"
        LAST_TITLE="Desktop"
        return 0
    fi
    return 1
}

watch_title() {
    local wid=$1
    LAST_TITLE="$(read_title_once "$wid" || true)"
    [ -z "$LAST_TITLE" ] && LAST_TITLE="Desktop"
    printf '%s\n' "$LAST_TITLE"
    stdbuf -oL -eL xprop -spy -id "$wid" _NET_WM_NAME WM_NAME 2>/dev/null \
        | awk -F'"' 'NF>=2{print $2}' &
    TITLE_WATCHER_PID=$!
}

cleanup_title_watcher() {
    if [ -n "${TITLE_WATCHER_PID:-}" ]; then
        kill "$TITLE_WATCHER_PID" 2>/dev/null || true
        TITLE_WATCHER_PID=""
    fi
}

main() {
    have xprop || { err "xprop not found"; exit 1; }

    local wid
    wid="$(get_active_wid || true)"
    if ! print_desktop_if_needed "$wid"; then
        watch_title "$wid"
    fi

    stdbuf -oL -eL xprop -root -spy _NET_ACTIVE_WINDOW 2>/dev/null \
        | while IFS= read -r line; do
            wid="$(printf '%s\n' "$line" | awk -F'#' 'NR==1{gsub(/[[:space:]]/, "", $2); print $2}')"
            cleanup_title_watcher
            if ! print_desktop_if_needed "$wid"; then
                watch_title "$wid"
            fi
        done
}

main "$@"
