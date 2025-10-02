#!/usr/bin/env bash
# xtmon.sh — Continuous output of the active X11 window title
# Events: focus changes and title changes (tab switches in the browser)
# If no active window: print "Desktop"
# Dependency: xprop (xorg-xprop)
# Exit with Ctrl-C

set -o errexit -o nounset -o pipefail
export LC_ALL=C

# shellcheck disable=SC1090
if [[ -r "$BASH_ENV" ]]; then
    # shellcheck source=lib/logging_env.sh
    source "$BASH_ENV"
else
    echo "logging_env.sh not found at: $BASH_ENV" >&2
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
LAST_TITLE=""

print_desktop_if_needed() {
    if [ "${LAST_TITLE:-}" != "Desktop" ]; then
        printf '%s\n' "Desktop"
        LAST_TITLE="Desktop"
    fi
}

start_title_watcher() {
    # $1 = WID
    local wid=$1 line title
    # Initialtitel sofort ausgeben (falls vorhanden)
    title="$(read_title_once "$wid")" || true
    if [ -n "${title:-}" ] && [ "${title}" != "${LAST_TITLE:-}" ]; then
        printf '%s\n' "$title"
        LAST_TITLE=$title
    fi
    (
        while IFS= read -r line; do
            title="$(printf '%s' "$line" | awk -F'"' 'NF>=2{print $2}')"
            if [ -n "${title:-}" ] && [ "${title}" != "${LAST_TITLE:-}" ]; then
                printf '%s\n' "$title"
                LAST_TITLE=$title
            fi
        done < <(xprop -spy -id "$wid" _NET_WM_NAME WM_NAME 2>/dev/null)
    ) &
    TITLE_WATCHER_PID=$!
}

stop_title_watcher() {
    if [ -n "${TITLE_WATCHER_PID:-}" ] && kill -0 "$TITLE_WATCHER_PID" 2>/dev/null; then
        kill "$TITLE_WATCHER_PID" 2>/dev/null || true
        sleep 0.05
        kill -9 "$TITLE_WATCHER_PID" 2>/dev/null || true
    fi
    TITLE_WATCHER_PID=""
    # Wichtig: LAST_TITLE NICHT zurücksetzen, damit Dedupe für "Desktop" greift
}

cleanup() {
    stop_title_watcher
    exit 0
}

if ! have xprop; then
    err "xprop nicht gefunden (xorg-xprop installieren)."
    exit 1
fi

trap cleanup INT TERM

current_wid="$(get_active_wid || true)"
if [ -z "${current_wid:-}" ] || [ "${current_wid}" = "0x0" ]; then
    # Kein aktives Fenster -> "Desktop" einmalig ausgeben
    print_desktop_if_needed
else
    start_title_watcher "$current_wid"
fi

# Auf Wechsel des aktiven Fensters lauschen
while IFS= read -r root_line; do
    new_wid="$(printf '%s' "$root_line" | awk -F'#' 'NR==1{gsub(/[[:space:]]/, "", $2); print $2}')"

    if [ -z "${new_wid:-}" ] || [ "${new_wid}" = "0x0" ]; then
        # Fokus ist auf dem Desktop (kein aktives Fenster)
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
done < <(xprop -spy -root _NET_ACTIVE_WINDOW 2>/dev/null)
