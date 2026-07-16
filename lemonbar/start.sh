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

    local loc="$1" rc="${2:-1}" cmd="${3:-}"
    local line="${loc%%/*}"
    log_error "line=${line:-0} rc=$rc cmd=$cmd"
    return "$rc"
}

# Remove a PID file only when it still belongs to the expected process.
remove_owned_pid_file() {
    local pid_file=$1 expected_pid=$2 recorded_pid

    [[ $expected_pid =~ ^[0-9]+$ && -r $pid_file ]] || return 0
    IFS= read -r recorded_pid <"$pid_file" || return 0
    [[ $recorded_pid == "$expected_pid" ]] || return 0
    rm -f -- "$pid_file"
}

# Publish a PID atomically so readers never observe partial contents.
publish_pid_file() {
    local pid_file=$1 pid=$2 temporary_file

    temporary_file="$pid_file.tmp.$$"
    printf '%s\n' "$pid" >"$temporary_file"
    chmod 600 -- "$temporary_file"
    mv -f -- "$temporary_file" "$pid_file"
}

# Wait until sighandler.sh confirms that all realtime traps are installed.
wait_for_sighandler() {
    local ready_file=$1 expected_pid=$2 deadline recorded_pid
    deadline=$((SECONDS + 5))

    while ((SECONDS < deadline)); do
        if [[ -r $ready_file ]]; then
            IFS= read -r recorded_pid <"$ready_file" || recorded_pid=""
            [[ $recorded_pid == "$expected_pid" ]] && return 0
        fi
        kill -0 "$expected_pid" 2>/dev/null || return 1
        sleep 0.01
    done

    return 1
}

# DESC: Terminate all directly managed child processes
# ARGS: None
# OUTS: None
terminate_children() {
    local pid

    # Stop data producers first.
    for pid in \
        "${events_pid:-}" \
        "${title_server_pid:-}" \
        "${sighandler_pid:-}"; do
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done

    for pid in \
        "${events_pid:-}" \
        "${title_server_pid:-}" \
        "${sighandler_pid:-}"; do
        if [[ "$pid" =~ ^[0-9]+$ ]]; then
            wait "$pid" 2>/dev/null || true
        fi
    done

    # Stop lemonbar after its producers.
    if [[ "${lemonbar_pid:-}" =~ ^[0-9]+$ ]]; then
        kill -TERM "$lemonbar_pid" 2>/dev/null || true
        wait "$lemonbar_pid" 2>/dev/null || true
    fi
}

# DESC: Exithandler
# ARGS: None
# OUTS: None
trap_exit() {
    local ec=$?

    trap - EXIT INT TERM QUIT HUP PIPE ERR
    set +o errexit
    set +o pipefail

    log_info "EXIT rc=$ec"

    terminate_children
    trap_cleanup

    cd "$orig_cwd" || true
    exit "$ec"
}

# DESC: Exit script with the given message
# ARGS: $1 (required): Message to print on exit
#       $2 (optional): Exit code (defaults to 0)
# OUTS: None
exit_handler() {
    if [[ $# -lt 1 || $# -gt 2 ]]; then
        printf '%s\n' 'Missing required argument to exit_handler()!' >&2
        exit 2
    fi

    local message="$1"
    local rc="${2:-0}"

    if [[ ! "$rc" =~ ^[0-9]+$ ]] || ((rc > 255)); then
        printf 'Invalid exit code: %s\n' "$rc" >&2
        exit 2
    fi

    printf '%b\n' "$message"

    if ((rc != 0)); then
        log_error "exit rc=$rc message=$message"
    fi

    exit "$rc"
}

# DESC: remove FIFO at termination
# ARGS: None
# OUTS: None
trap_cleanup() {
    trap - TERM

    # Remove only PID files still owned by this instance.
    remove_owned_pid_file "${sighandler_pid_file:-}" "${sighandler_pid:-}"
    remove_owned_pid_file "${script_lock:-}" "$$"

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
     -l|--log                   Enables INFO and ERROR logging
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
            LOG_INFO_ENABLED=1
            export LOG_INFO_ENABLED
            ;;
        *)
            exit_handler "Invalid parameter was provided: $param" 1
            ;;
        esac
    done
}

# Return success if a PID belongs to a Lemonbar start.sh process.
pid_is_lemonbar_start() {
    local pid=$1 argument
    local -a arguments=()

    [[ $pid =~ ^[0-9]+$ && -r /proc/$pid/cmdline ]] || return 1
    mapfile -d '' -t arguments <"/proc/$pid/cmdline" || return 1

    for argument in "${arguments[@]}"; do
        case $argument in
        "$LEMONDIR/start.sh" | ./start.sh | start.sh) return 0 ;;
        esac
    done

    return 1
}

# Create this instance's lock file without replacing an existing file.
create_lock_file() {
    local pid_file=$1

    if (
        set -o noclobber
        printf '%s\n' "$$" >"$pid_file"
    ) 2>/dev/null; then
        if ! chmod 600 -- "$pid_file"; then
            rm -f -- "$pid_file"
            return 1
        fi
        script_lock=$pid_file
        return 0
    fi

    return 1
}

# DESC: Acquire script lock via PID file in LEMONBAR_RUNTIME_DIR
# ARGS: none
# OUTS: $script_lock: Path to the PID file that represents the lock
# NOTE: Uses O_EXCL-style creation (noclobber) to avoid races.
lock_init() {
    if [[ ! -d $LEMONBAR_RUNTIME_DIR || ! -w $LEMONBAR_RUNTIME_DIR ]]; then
        printf 'Runtime dir not usable: %s\n' "$LEMONBAR_RUNTIME_DIR" >&2
        return 2
    fi

    local pid_file="$LEMONBAR_RUNTIME_DIR/start.pid"
    local old_pid

    create_lock_file "$pid_file" && return 0

    # Keep a live Lemonbar lock, but reclaim invalid or stale PID files.
    if [[ -r "$pid_file" ]]; then
        IFS= read -r old_pid <"$pid_file" || old_pid=""
        if [[ $old_pid =~ ^[0-9]+$ ]] &&
            kill -0 "$old_pid" 2>/dev/null &&
            pid_is_lemonbar_start "$old_pid"; then
            printf 'Unable to acquire lock: %s (pid=%s)\nLOCKBUSY (200)\n' \
                "$pid_file" "$old_pid" >&2
            return 200
        fi

        rm -f -- "$pid_file"
        create_lock_file "$pid_file" && return 0
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
    export LEMONBAR_RUNTIME_DIR="${LEMONBAR_RUNTIME_DIR:-$XDG_RUNTIME_DIR/lemonbar}"

    mkdir -p -- "$LEMONBAR_RUNTIME_DIR"
    chmod 700 -- "$LEMONBAR_RUNTIME_DIR"

    # shellcheck disable=SC1090
    if [[ -r "$BASH_ENV" ]]; then
        # shellcheck source=lib/logging_env.sh
        source "$BASH_ENV"
    else
        echo "logging_env.sh not found at: $BASH_ENV" >&2
    fi
}

# DESC: Wait for the first critical child process to exit
# ARGS: None
# OUTS: None
# NOTE: Any child exit stops the complete panel to avoid a partial session.
monitor_children() {
    local exited_pid rc exit_rc child_name

    if wait -n -p exited_pid \
        "$lemonbar_pid" \
        "$sighandler_pid" \
        "$events_pid" \
        "$title_server_pid"; then
        rc=0
    else
        rc=$?
    fi

    case "${exited_pid:-}" in
    "$lemonbar_pid")
        child_name="lemonbar"
        ;;
    "$sighandler_pid")
        child_name="sighandler.sh"
        remove_owned_pid_file "$sighandler_pid_file" "$sighandler_pid"
        ;;
    "$events_pid")
        child_name="events.sh"
        ;;
    "$title_server_pid")
        child_name="title_server.sh"
        ;;
    *)
        child_name="unknown"
        ;;
    esac

    if ((rc == 0)); then
        log_error "unexpected child exit: name=$child_name pid=${exited_pid:-unknown} rc=0"
        exit_rc=1
    else
        log_error "child exit: name=$child_name pid=${exited_pid:-unknown} rc=$rc"
        exit_rc=$rc
    fi

    exit "$exit_rc"
}

# DESC: Main control flow
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: None
main() {
    trap 'trap_err "${LINENO}/${BASH_LINENO[0]:-0}" "$?" "$BASH_COMMAND"' ERR
    trap 'trap_exit' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 0' QUIT HUP PIPE

    tmp_dir=""
    fifo=""
    lemonbar_pid=""
    sighandler_pid=""
    events_pid=""
    title_server_pid=""
    sighandler_pid_file=""
    sighandler_ready_file=""

    init "$@"
    parse_params "$@"
    log_info "initialized" "$0"

    tmp_dir=$(mktemp -p "$TMPDIR" -d lemonbar.XXXX)

    if lock_init; then
        :
    else
        rc=$?
        exit "$rc"
    fi

    # shellcheck disable=SC1091
    source "$LEMONDIR/config.sh"
    # shellcheck source=panel_runtime.sh
    source "$LEMONDIR/panel_runtime.sh"

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
        -u "$UNDERLINE_HEIGHT" -n "$PANEL_WM_NAME" \
        <"$fifo" > >(bash) &
    lemonbar_pid=$!

    export tmp_dir
    sighandler_ready_file="$tmp_dir/sighandler.ready"
    export SIGHANDLER_READY_FILE="$sighandler_ready_file"
    # fifo-writer, starting after reader
    "$LEMONDIR/sighandler.sh" >"$fifo" &
    sighandler_pid=$!

    if ! wait_for_sighandler "$sighandler_ready_file" "$sighandler_pid"; then
        log_error "sighandler failed before becoming ready: pid=$sighandler_pid"
        exit 1
    fi

    # Publish the signal receiver PID for sxhkd and helper scripts.
    sighandler_pid_file="$LEMONBAR_RUNTIME_DIR/sighandler.pid"
    publish_pid_file "$sighandler_pid_file" "$sighandler_pid"

    "$LEMONDIR/events.sh" "$sighandler_pid" &
    events_pid=$!

    "$LEMONDIR/title_server.sh" "$sighandler_pid" &
    title_server_pid=$!

    # Stop the complete panel as soon as one critical child exits.
    monitor_children
}

main "$@"

# vim: syntax=sh cc=80 tw=79 ts=4 sw=4 sts=4 et sr
