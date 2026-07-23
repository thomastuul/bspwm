#!/usr/bin/env bash

#set -x

set -euo pipefail

# shellcheck disable=SC1091
source "$HOME/.config/bspwm/lemonbar/config.sh"
# shellcheck disable=SC1091
source "$HOME/.config/bspwm/lemonbar/panel_runtime.sh"

: "${XDG_RUNTIME_DIR:="/run/user/$(id -u)"}"
BSPWM_RUNTIME_DIR="${BSPWM_RUNTIME_DIR:-$XDG_RUNTIME_DIR/bspwm}"
mkdir -p -- "$BSPWM_RUNTIME_DIR"
chmod 700 -- "$BSPWM_RUNTIME_DIR"

pidfile="$BSPWM_RUNTIME_DIR/trayer.pid"
trayer_pid=""

cleanup() {
    # trayer beenden, falls noch läuft
    if [[ -n "${trayer_pid:-}" ]] && kill -0 "$trayer_pid" 2>/dev/null; then
        kill -TERM "$trayer_pid" 2>/dev/null || true
        wait "$trayer_pid" 2>/dev/null || true
    fi
    rm -f -- "$pidfile"
}
trap cleanup EXIT INT TERM

# DESC: Stop old trayer instance if pidfile exists
stop_old_trayer() {
    if [[ -r "$pidfile" ]]; then
        local old_pid
        old_pid=$(<"$pidfile")
        if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
            kill -TERM "$old_pid"
            # Wait briefly for process to exit
            sleep 0.5
            if kill -0 "$old_pid" 2>/dev/null; then
                kill -KILL "$old_pid"
            fi
        fi
    fi
}

stop_old_trayer

# shellcheck disable=SC2154
color="0x${Background#\#}"

trayer --edge top --align right --SetDockType true \
    --SetPartialStrut true --expand true --transparent true \
    --alpha 1.0 --tint "$color" --widthtype request \
    --width 3 --height "$PANEL_HEIGHT" --distancefrom right --distance 35 &

trayer_pid=$!
printf '%s\n' "$trayer_pid" >"$pidfile"

wait "$trayer_pid"