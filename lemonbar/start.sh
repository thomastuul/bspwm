#!/usr/bin/env bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

#set -o errexit      # Exit on most errors (see the manual)
set -o nounset      # Disallow expansion of unset variables
set -o pipefail     # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
set -o errtrace     # Ensure the error trap handler is inherited

trap_err_triggered=false

# DESC:
# ARGS: None
# OUTS: None
script_trap_err() {
    local parent_lineno="$1"
    local code="$2"
    local commands="$3"
    trap_err_triggered=true
    echo "Error exit status $code, at file $0 on or near line $parent_lineno: $commands"
}

# DESC:
# ARGS: None
# OUTS: None
script_trap_exit() {
    # Kill all subprocesses (all processes in the current process group)
    kill -HUP -$$
    if [ "$trap_err_triggered" = false ]; then
        echo "Exit $0"
    fi
}

# DESC: remove FIFO at termination
# ARGS: None
# OUTS: None
script_trap_cleanup() {
    if [[ -e "$fifo" ]]; then
        rm "$fifo"
    fi
    printf "%s stopped\n" "$0"
}

# DESC: Usage help
# ARGS: None
# OUTS: None
script_usage() {
    cat << EOF
Usage:
     -h|--help                  Displays this help
     -v|--verbose               Displays verbose output
    -nc|--no-colour             Disables colour output
    -cr|--cron                  Run silently unless we encounter an error
EOF
}

# DESC: Parameter parser
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: Variables indicating command-line parameters and options
parse_params() {
    local param
    while [[ $# -gt 0 ]]; do
        param="$1"
        shift
        case $param in
            -h | --help)
                script_usage
                exit 0
                ;;
            -v | --verbose)
                verbose=true
                ;;
            -nc | --no-colour)
                no_colour=true
                ;;
            -cr | --cron)
                cron=true
                ;;
            *)
                script_exit "Invalid parameter was provided: $param" 1
                ;;
        esac
    done
}

# DESC: Initialise Cron mode
# ARGS: None
# OUTS: $script_output: Path to the file stdout & stderr was redirected to
cron_init() {
    if [[ -n ${cron-} ]]; then
        # Redirect all output to a temporary file
        script_output="$(touch "$tmp_dir"/lemonbar.log)"
        readonly script_output
        exec 3>&1 4>&2 1> "$script_output" 2>&1
    fi
}

# DESC: Acquire script lock
# ARGS: $1 (optional): Scope of script execution lock (system or user)
# OUTS: $script_lock: Path to the directory indicating we have the script lock
# NOTE: This lock implementation is extremely simple but should be reliable
#       across all platforms. It does *not* support locking a script with
#       symlinks or multiple hardlinks as there's no portable way of doing so.
#       If the lock was acquired it's automatically released on script exit.
lock_init() {
    local lock_dir
    if [[ $1 = 'system' ]]; then
        lock_dir="/tmp/$script_name.lock"
    elif [[ $1 = 'user' ]]; then
        lock_dir="/tmp/$script_name.$UID.lock"
    else
        script_exit 'Missing or invalid argument to lock_init()!' 2
    fi

    if mkdir "$lock_dir" 2> /dev/null; then
        readonly script_lock="$lock_dir"
        verbose_print "Acquired script lock: $script_lock"
    else
        script_exit "Unable to acquire script lock: $lock_dir" 1
    fi
}

# DESC: Main control flow
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: None
main() {
    trap 'script_trap_err "${LINENO}/${BASH_LINENO}" "$?" "$BASH_COMMAND"'  ERR
    trap script_trap_exit                                                   EXIT
    trap script_trap_cleanup                                                INT TERM QUIT

#    parse_params "$@"

    export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
    export TMPDIR="${TMPDIR:-/tmp}"
    export LEMONDIR="${XDG_CONFIG_HOME}/bspwm/lemonbar"

    tmp_dir=$(mktemp -p "$TMPDIR" -d lemonbar.XXXX)

    #lock_init system
#    cron_init

    source "$LEMONDIR/config.sh"

#    if [[ $(pgrep -cx lemonbar) -gt 0 ]] ; then
#        printf "%s\n" "The panel is already running." >&2
#        exit 1
#    fi

    # create named pipe
    fifo="${tmp_dir}/lemonbar.fifo"
    if [[ -e "$fifo" ]]; then
        rm "$fifo"
    fi
    mkfifo "$fifo"

    "$LEMONDIR/sighandler.sh" "$tmp_dir" "$LEMONDIR" > "$fifo" &
    sighandler_pid=$!

    lemonbar -p -a "$CLICKABLE_AREAS" \
        -g "$PANEL_WIDTH"x"$PANEL_HEIGHT"+"$PANEL_HORIZONTAL_OFFSET"+"$PANEL_VERTICAL_OFFSET" \
        -f "$PANEL_FONT" -f "$PANEL_ICON_FONT" -F "$COLOR_DEFAULT_FG" -B "$COLOR_PANEL_BG" \
        -u "$UNDERLINE_HEIGHT" -n "$PANEL_WM_NAME" < "$fifo" | sh &

    sighandler_pid="$sighandler_pid" tmp_Dir="$tmp_dir" "$LEMONDIR/events.sh" &
    events_pid=$!

    wait $events_pid
}

# Invoke main with args if not sourced
# Approach via: https://stackoverflow.com/a/28776166/8787985
if ! (return 0 2> /dev/null); then
    main "$@"
fi

# vim: syntax=sh cc=80 tw=79 ts=4 sw=4 sts=4 et sr
