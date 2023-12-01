#!/usr/bin/env bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

set -o errexit      # Exit on most errors (see the manual)
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
    echo "Error exit status $code (SIG$(kill -l $code)), at file $0 on or near line $parent_lineno: $commands"
}

# DESC: Handler for exiting the script
# ARGS: None
# OUTS: None
script_trap_exit() {
    cd "$orig_cwd"

    # Remove Log mode script log
    #if [[ -n ${log-} && -f ${script_output-} ]]; then
    #    rm "$script_output"
    #fi

    # Remove script execution lock
    if [[ -d ${script_lock-} ]]; then
        rmdir "$script_lock"
    fi

    # Kill all subprocesses (all processes in the current process group)
    kill -HUP -$$
    if [ "$trap_err_triggered" = false ]; then
        echo "Exit $0"
    fi
}

# DESC: Exit script with the given message
# ARGS: $1 (required): Message to print on exit
#       $2 (optional): Exit code (defaults to 0)
# OUTS: None
# NOTE: The convention used in this script for exit codes is:
#       0: Normal exit
#       1: Abnormal exit due to external error
#       2: Abnormal exit due to script error
script_exit() {
    if [[ $# -eq 1 ]]; then
        printf '%s\n' "$1"
        exit 0
    fi

    if [[ ${2-} =~ ^[0-9]+$ ]]; then
        printf '%b\n' "$1"
        # If we've been provided a non-zero exit code run the error trap
        if [[ $2 -ne 0 ]]; then
            script_trap_err "$2"
        else
            exit 0
        fi
    fi

    script_exit 'Missing required argument to script_exit()!' 2
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
     -l|--log                   Run silently unless we encounter an error
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
            -l | --log)
                log=true
                ;;
            *)
                script_exit "Invalid parameter was provided: $param" 1
                ;;
        esac
    done
}

# DESC: Initialise log mode
# ARGS: None
# OUTS: $script_output: Path to the file stdout & stderr was redirected to
log_init() {
    if [[ -n ${log-} ]]; then
        # Redirect all output to a temporary file
        script_output=""$tmp_dir"/lemonbar.log"
        touch "$tmp_dir"/lemonbar.log
        #readonly script_output
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
        printf "%s\n" "Acquired script lock: $script_lock"
    else
        script_exit "Unable to acquire script lock: $lock_dir" 1
    fi
}

# DESC: Generic script initialisation
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: $orig_cwd: The current working directory when the script was run
#       $script_path: The full path to the script
#       $script_dir: The directory path of the script
#       $script_name: The file name of the script
#       $script_params: The original parameters provided to the script
# NOTE: $script_path only contains the path that was used to call the script
#       and will not resolve any symlinks which may be present in the path.
#       You can use a tool like realpath to obtain the "true" path. The same
#       caveat applies to both the $script_dir and $script_name variables.
# shellcheck disable=SC2034
script_init() {
    # Useful variables
    readonly orig_cwd="$PWD"
    readonly script_params="$*"
    readonly script_path="${BASH_SOURCE[0]}"
    script_dir="$(dirname "$script_path")"
    script_name="$(basename "$script_path")"
    readonly script_dir script_name
}

# DESC: Main control flow
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: None
main() {
    trap 'script_trap_err "${LINENO}/${BASH_LINENO}" "$?" "$BASH_COMMAND"'  ERR
    trap script_trap_exit                                                   EXIT
    trap script_trap_cleanup                                                INT TERM QUIT

    export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
    export TMPDIR="${TMPDIR:-/tmp}"
    export LEMONDIR="${XDG_CONFIG_HOME}/bspwm/lemonbar"

    tmp_dir=$(mktemp -p "$TMPDIR" -d lemonbar.XXXX)

    script_init
    parse_params "$@"
    log_init
    lock_init user

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

main "$@"

# vim: syntax=sh cc=80 tw=79 ts=4 sw=4 sts=4 et sr
