#!/usr/bin/env bash

# vim: syntax=bash

# source-path=SCRIPTDIR

cleanup() {
    if [[ -e "$fifo" ]]; then
        rm "$fifo"
    fi
    printf "%s stopped\n" "$0"
    # Disable the termination trap handler to prevent potential recursion
    trap - TERM
    kill 0
}

log() {
    echo "$1" >> "$LOG_FILE"
}

# trap 0 -> hook for closing/terminating shell
trap 'cleanup' INT TERM QUIT EXIT 0

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export TMPDIR="${TMPDIR:-/tmp}"
export LEMONDIR="${XDG_CONFIG_HOME}/bspwm/lemonbar"

tmp_dir=$(mktemp -p "$TMPDIR" -d lemonbar.XXXX)

LOG_FILE="$tmp_dir/lemonbar.log"

source "$LEMONDIR/config.sh"

touch "$LOG_FILE"

if [[ $(pgrep -cx lemonbar) -gt 0 ]] ; then
    printf "%s\n" "The panel is already running." >&2
    log "exit, panel already spawned"
    exit 1
fi

# create named pipe
fifo="${tmp_dir}/lemonbar.fifo"
if [[ -e "$fifo" ]]; then
    rm "$fifo"
fi
mkfifo "$fifo"

lemondir="$LEMONDIR" tmp_Dir="$tmp_dir" "$LEMONDIR/sighandler.sh" > "$fifo" &
sighandler_pid=$!

log "sighandler spawned"

lemonbar -p -a "$CLICKABLE_AREAS" \
    -g "$PANEL_WIDTH"x"$PANEL_HEIGHT"+"$PANEL_HORIZONTAL_OFFSET"+"$PANEL_VERTICAL_OFFSET" \
    -f "$PANEL_FONT" -f "$PANEL_ICON_FONT" -F "$COLOR_DEFAULT_FG" -B "$COLOR_PANEL_BG" \
    -u "$UNDERLINE_HEIGHT" -n "$PANEL_WM_NAME" < "$fifo" | sh &

log "lemonbar spawned"

# Send signal for update lemonbar workspaces at event desktop change
get_ws_updates_changed_desktop() {
    bspc subscribe desktop_focus | while read -r; do
        kill -RTMIN+2 "$sighandler_pid"
    done
}

get_ws_updates_changed_desktop &

# Send signal for update lemonbar workspaces at event node transfer to different desktop
get_ws_updates_node_transfer() {
    bspc subscribe node_transfer | while read -r; do
        kill -RTMIN+2 "$sighandler_pid"
    done
}

get_ws_updates_node_transfer &

# Send signal for update lemonbar workspaces at layout change
get_ws_updates_layout_change() {
    bspc subscribe desktop_layout | while read -r; do
        kill -RTMIN+2 "$sighandler_pid"
    done
}

get_ws_updates_layout_change &

get_trayer_updates() {
    # wait until trayer has started
    while ! pidof trayer > /dev/null; do
        sleep 1
    done

    xprop -name panel -spy | grep --line-buffered 'program specified minimum size' | while IFS= read -r line; do
        kill -RTMIN+9 "$sighandler_pid"
    done
}

get_trayer_updates &

get_new_node_update() {
    bspc subscribe node_add | while read -r; do
        kill -RTMIN+2 "$sighandler_pid"
    done
}

get_new_node_update &

tmp_Dir="$tmp_dir" "$LEMONDIR/title_server.sh" &

wait
