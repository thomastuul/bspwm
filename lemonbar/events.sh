#!/usr/bin/env bash

#set -x

#set -o errexit      # Exit on most errors (see the manual)
set -o nounset      # Disallow expansion of unset variables
set -o pipefail     # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
set -o errtrace     # Ensure the error trap handler is inherited

# DESC:
# ARGS: None
# OUTS: None
script_trap_err() {
    local parent_lineno="$1"
    local code="$2"
    local commands="$3"
    echo "Error exit status $code, at file $0 on or near line $parent_lineno: $commands"
}

# Send signal for update lemonbar workspaces at event desktop change
get_ws_updates_changed_desktop() {
    bspc subscribe desktop_focus | while read -r; do
        kill -RTMIN+2 "$sighandler_pid"
    done
}

# Send signal for update lemonbar workspaces at event node transfer to different desktop
get_ws_updates_node_transfer() {
    bspc subscribe node_transfer | while read -r; do
        kill -RTMIN+2 "$sighandler_pid"
    done
}

# Send signal for update lemonbar workspaces at layout change
get_ws_updates_layout_change() {
    bspc subscribe desktop_layout | while read -r; do
        kill -RTMIN+2 "$sighandler_pid"
    done
}

get_trayer_updates() {
    # wait until trayer has started
    while ! pidof trayer > /dev/null; do
        sleep 1
    done

    xprop -name panel -spy | grep --line-buffered 'program specified minimum size' | while IFS= read -r line; do
        kill -RTMIN+9 "$sighandler_pid"
    done
}

get_new_node_updates() {
    bspc subscribe node_add | while read -r; do
        kill -RTMIN+2 "$sighandler_pid"
    done
}

trap 'script_trap_err "${LINENO}/${BASH_LINENO}" "$?" "$BASH_COMMAND"'  ERR

get_ws_updates_changed_desktop &
get_ws_updates_node_transfer &
get_ws_updates_layout_change &
get_trayer_updates &
get_new_node_updates &

tmp_Dir="$tmp_Dir" "$LEMONDIR/title_server.sh"
