#!/usr/bin/env bash

trap 'kill $(jobs -pr) 2>/dev/null' EXIT
trap 'kill $(jobs -pr) 2>/dev/null; exit 0' INT TERM HUP

export LC_ALL=C

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

set -o errexit      # Exit on most errors (see the manual)
set -o nounset      # Disallow expansion of unset variables
set -o pipefail     # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
set -o errtrace     # Ensure the error trap handler is inherited

# DESC: Errorhandler
# ARGS: $1: Line number of err occurence
#       $2: Exit status code
#       $3: invoked command
# OUTS: None
script_trap_err() {
    local parent_lineno="$1"
    local code="$2"
    local commands="$3"
    echo "Error exit status $code, at file $0 on or near line $parent_lineno: $commands"
}

# Send signal for update lemonbar workspaces at event desktop change
get_ws_updates_changed_desktop() {
    stdbuf -oL -eL bspc subscribe desktop_focus | while read -r; do
        # shellcheck disable=SC2154
        kill -RTMIN+2 "$sighandler_pid"
    done
}

# Send signal for update lemonbar workspaces at event node transfer to different desktop
get_ws_updates_node_transfer() {
    stdbuf -oL -eL bspc subscribe node_transfer | while read -r; do
        kill -RTMIN+2 "$sighandler_pid"
    done
}

# Send signal for update lemonbar workspaces at layout change
get_ws_updates_layout_change() {
    stdbuf -oL -eL bspc subscribe desktop_layout | while read -r; do
        kill -RTMIN+2 "$sighandler_pid"
    done
}

get_trayer_updates() {
    # wait until trayer has started
    while ! pidof trayer > /dev/null; do
        sleep 1
    done

    stdbuf -oL -eL xprop -name "$PANEL_WM_NAME" -spy | grep --line-buffered 'program specified minimum size' | while IFS= read -r; do
        kill -RTMIN+9 "$sighandler_pid"
    done
}

get_new_node_updates() {
    stdbuf -oL -eL bspc subscribe node_add | while read -r; do
        kill -RTMIN+2 "$sighandler_pid"
    done
}

trap 'script_trap_err "${LINENO}/${BASH_LINENO}" "$?" "$BASH_COMMAND"'  ERR

get_ws_updates_changed_desktop &
get_ws_updates_node_transfer &
get_ws_updates_layout_change &
get_trayer_updates &
get_new_node_updates &

# shellcheck disable=SC2154
tmp_dir="$tmp_dir" sighandler_pid="$sighandler_pid" "$LEMONDIR/title_server.sh"
