#!/usr/bin/env bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    #export PS4='+ $(date "+%F %T") ${BASH_SOURCE##*/}:${LINENO}: '
    #export BASH_XTRACEFD=3
    set -o xtrace # Trace the execution of the script (debug)
fi

set -o errexit            # Exit on most errors (see the manual)
set -o nounset            # Disallow expansion of unset variables
set -o pipefail           # Use last non-zero exit code in a pipeline
shopt -s lastpipe || true # Don't use subshell after pipe and never fail
# Enable errtrace or the error trap handler will not work as expected
set -o errtrace # Ensure the error trap handler is inherited

# DESC: Errorhandler
# ARGS: $1: line number of err occurence.
#       $2: Exit status code
#       $3: invoked command
# OUTS: None
trap_err() {
    # Disable the error trap handler to prevent potential recursion
    trap - ERR

    # Consider any further errors non-fatal to ensure we run to completion
    set +o errexit
    set +o pipefail

    local loc="$1" rc="${2:-1}" cmd="${3:-}"
    local line="${loc%%/*}"
    log_error "line=${line:-0} rc=$rc cmd=$cmd"
}

# DESC: Exithandler
# ARGS: None
# OUTS: None
trap_exit() {
    local ec=$?
    log_info "EXIT" "$ec"

    cd "$orig_cwd"

    # terminate entire process group
    kill -TERM -- -$$ 2>/dev/null || true
    sleep 0.2
    kill -KILL -- -$$ 2>/dev/null || true

    wait || true
}

# DESC: Exit script with the given message
# ARGS: $1 (required): Message to print on exit
#       $2 (optional): Exit code (defaults to 0)
# OUTS: None
# NOTE: The convention used in this script for exit codes is:
#       0: Normal exit
#       1: Abnormal exit due to external error
#       2: Abnormal exit due to script error
exit_handler() {
    if [[ $# -eq 1 ]]; then
        printf '%s\n' "$1"
        exit 0
    fi

    if [[ ${2-} =~ ^[0-9]+$ ]]; then
        printf '%b\n' "$1"
        # If we've been provided a non-zero exit code run the error trap
        if [[ $2 -ne 0 ]]; then
            trap_err "$2"
        else
            exit 0
        fi
    fi

    exit_handler 'Missing required argument to exit_handler()!' 2
}

# DESC: remove FIFO at termination
# ARGS: None
# OUTS: None
trap_cleanup() {
    trap - TERM

    # PID-Datei entfernen
    if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
        rm -f "$XDG_RUNTIME_DIR/sighandler.pid"
        if [ -n "${script_lock-}" ] && [ -e "${script_lock-}" ]; then
            rm -f -- "$script_lock"
        fi
    fi

    # FIFO entfernen
    if [ -n "${fifo:-}" ] && [ -e "$fifo" ]; then
        rm -f "$fifo"
    fi

    # tmp_dir entfernen
    if [ -n "${tmp_dir:-}" ] && [ -d "$tmp_dir" ]; then
        rm -rf "$tmp_dir"
    fi

    printf "%s stopped\n" "$0"
}

# DESC: Usage help
# ARGS: None
# OUTS: None
usage() {
    cat <<EOF
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
            # Disable EXIT trap so help does not trigger cleanup
            trap - EXIT
            usage
            exit 0
            ;;
        -l | --log)
            log=true
            ;;
        *)
            exit_handler "Invalid parameter was provided: $param" 1
            ;;
        esac
    done
}

# DESC: Acquire script lock via PID file in XDG_RUNTIME_DIR
# ARGS: none
# OUTS: $script_lock: Path to the PID file that represents the lock
# NOTE: Uses O_EXCL-style creation (noclobber) to avoid races.
lock_init() {
    if [[ ! -d $XDG_RUNTIME_DIR || ! -w $XDG_RUNTIME_DIR ]]; then
        printf 'Runtime dir not usable: %s\n' "$XDG_RUNTIME_DIR" >&2
        return 2
    fi

    local pid_file="$XDG_RUNTIME_DIR/start.sh.pid"
    local old_pid

    # Try to create atomically (noclobber) and write PID in one step
    if (
        set -o noclobber
        printf '%s\n' "$$" >"$pid_file"
    ) 2>/dev/null; then
        chmod 600 -- "$pid_file" 2>/dev/null || true
        script_lock="$pid_file"
        return 0
    fi

    # PID file exists: check if stale
    if [[ -r "$pid_file" ]]; then
        old_pid="$(<"$pid_file")"
        if [[ "$old_pid" =~ ^[0-9]+$ ]]; then
            if kill -0 "$old_pid" 2>/dev/null; then
                printf 'Unable to acquire lock: %s (pid=%s)\nLOCKBUSY (200)\n' \
                    "$pid_file" "$old_pid" >&2
                return 200
            else
                rm -f -- "$pid_file"
                if (
                    set -o noclobber
                    printf '%s\n' "$$" >"$pid_file"
                ) 2>/dev/null; then
                    chmod 600 -- "$pid_file" 2>/dev/null || true
                    script_lock="$pid_file"
                    return 0
                fi
            fi
        else
            rm -f -- "$pid_file"
            if (
                set -o noclobber
                printf '%s\n' "$$" >"$pid_file"
            ) 2>/dev/null; then
                chmod 600 -- "$pid_file" 2>/dev/null || true
                script_lock="$pid_file"
                return 0
            fi
        fi
    fi

    printf 'Unable to acquire script lock: %s\n' "$pid_file" >&2
    return 200
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
init() {
    # Useful variables
    readonly orig_cwd="$PWD"
    readonly script_params="$*"
    readonly script_path="${BASH_SOURCE[0]}"
    script_dir="$(dirname "$script_path")"
    script_name="$(basename "$script_path")"
    readonly script_dir script_name
    export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
    export TMPDIR="${TMPDIR:-/tmp}"
    export LEMONDIR="${XDG_CONFIG_HOME}/bspwm/lemonbar"
    export BASH_ENV="$LEMONDIR/lib/logging_env.sh"
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"

    # shellcheck disable=SC1090
    if [[ -r "$BASH_ENV" ]]; then
        # shellcheck source=lib/logging_env.sh
        source "$BASH_ENV"
    else
        echo "logging_env.sh not found at: $BASH_ENV" >&2
    fi
}

# DESC: Main control flow
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: None
main() {
    trap 'trap_err "${LINENO}/${BASH_LINENO}" "$?" "$BASH_COMMAND"' ERR
    trap 'trap_exit; trap_cleanup' EXIT
    trap 'trap_cleanup; exit 130' INT
    trap 'trap_cleanup; exit 143' TERM
    trap 'trap_cleanup; exit 0' QUIT HUP PIPE

    tmp_dir=""
    fifo=""

    init "$@"
    log_info "Initializing Lemonbar"
    parse_params "$@"

    tmp_dir=$(mktemp -p "$TMPDIR" -d lemonbar.XXXX)

    if ! lock_init user; then
        rc=$? # Returncode of lock_init
        exit "$rc"
    fi

    # shellcheck disable=SC1091
    source "$LEMONDIR/config.sh"

    # create named pipe
    fifo="${tmp_dir}/lemonbar.fifo"
    readonly fifo
    if [[ -e "$fifo" ]]; then
        rm -f "$fifo"
    fi
    mkfifo -m 600 "$fifo"

    # fifo-reader, starting first
    lemonbar -p -a "$CLICKABLE_AREAS" \
        -g "$PANEL_WIDTH"x"$PANEL_HEIGHT"+"$PANEL_HORIZONTAL_OFFSET"+"$PANEL_VERTICAL_OFFSET" \
        -f "$PANEL_FONT" -f "$PANEL_ICON_FONT" -F "$COLOR_DEFAULT_FG" -B "$COLOR_PANEL_BG" \
        -u "$UNDERLINE_HEIGHT" -n "$PANEL_WM_NAME" <"$fifo" | bash || true &

    export tmp_dir
    # fifo-writer, starting after reader
    "$LEMONDIR/sighandler.sh" >"$fifo" &
    sighandler_pid=$!

    # file for exchanging sighandler_pid to sxhkd
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        echo "$sighandler_pid" >"$XDG_RUNTIME_DIR/sighandler.pid"
    fi

    "$LEMONDIR/events.sh" "$sighandler_pid" &
    "$LEMONDIR/title_server.sh" "$sighandler_pid" &

    # wait for subprocesses to be finished except one fails
    while :; do
        if ! wait -n; then
            rc=$?
            log_info "child_exit" "$rc"
        fi
        # wenn keine Jobs mehr: raus
        [[ -z "$(jobs -pr)" ]] && break
    done
}

main "$@"

# vim: syntax=sh cc=80 tw=79 ts=4 sw=4 sts=4 et sr
