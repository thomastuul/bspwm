# shellcheck shell=bash
# --- logging_env.sh -----------------------------------------------------------
# Purpose: Minimal logging bootstrap for lemonbar scripts.
# Behavior: Provides log_init(), log_info(), log_err(), and trap installation
#           without clobbering existing traps. 24h timestamps. Writes to
#           $TMPDIR by default.
# Usage:
#   source "${LEMONDIR}/lib/logging_env.sh"
#   LOGGING_ENV_AUTO=1  # optional auto-bootstrap
#   log_init            # or call explicitly
#   install_logging_traps
# ------------------------------------------------------------------------------

# Default temp dir
if [[ -z "${TMPDIR:-}" ]]; then
    TMPDIR="/tmp"
fi
export TMPDIR

# Script name for log lines
if [[ -z "${script_name:-}" ]]; then
    script_name="$(basename "$0")"
fi

# Default log file
if [[ -z "${LOG_FILE:-}" ]]; then
    LOG_FILE="$TMPDIR/lemonbar.$(date +'%F_%H-%M-%S').log"
fi
export LOG_FILE

# ---- internal helpers --------------------------------------------------------

_ts() {
    # 24h timestamp
    date +'%F %T'
}

# Append a command to an existing trap for a signal without overwriting it
_trap_add() {
    # $1: SIGNAL, $2...: command to append
    local sig="$1"
    shift
    local add cmd existing
    add="$*"

    # shellcheck disable=SC2046
    existing="$(trap -p "$sig" | awk -F"'" '{print $2}')"
    if [[ -n "$existing" ]]; then
        cmd="$existing; $add"
    else
        cmd="$add"
    fi
    trap -- "$cmd" "$sig"
}

# ---- public API --------------------------------------------------------------

# Initialize logging. Opens FD 3 for appends. Idempotent.
log_init() {
    # Create parent dir if needed
    mkdir -p -- "$TMPDIR"

    # Touch file before opening FD to avoid race warnings
    : >"$LOG_FILE"

    # Open append FD if not already open
    if ! { true >&3; } 2>/dev/null; then
        # shellcheck disable=SC3033
        exec 3>>"$LOG_FILE"
    fi

    # Header line
    printf '%s\t%s\t%s\t%s\n' "$(_ts)" "$script_name" "log_init" "0" >&3
}

# Generic writer
_log_write() {
    # $1 level, $2 message, $3 rc
    local lvl msg rc
    lvl="$1"
    msg="$2"
    rc="${3:-0}"

    # Ensure FD 3 exists if someone forgot log_init
    if ! { true >&3; } 2>/dev/null; then
        log_init
    fi

    printf '%s\t%s\t%s\t%s\n' "$(_ts)" "$script_name" "$lvl: $msg" "$rc" >&3
}

# Info message
log_info() {
    # $1 message, [$2 rc]
    _log_write "INFO" "${1:-}" "${2:-0}"
}

# Error message with line number and return code
log_err() {
    # $1 lineno, [$2 rc]
    local ln rc
    ln="${1:-0}"
    rc="${2:-1}"
    _log_write "ERROR" "line=$ln" "$rc"
}

# Install ERR/EXIT traps alongside any existing handlers.
install_logging_traps() {
    # ERR: capture $? at trap entry, then log with $LINENO
    # shellcheck disable=SC2016
    _trap_add ERR 'ec=$?; log_err "$LINENO" "$ec"'

    # EXIT: log final rc and close FD 3 if open
    # shellcheck disable=SC2016
    _trap_add EXIT 'ec=$?; log_info "exit" "$ec"; { true >&3; } 2>/dev/null && exec 3>&-'
}

# Optional automatic bootstrap if explicitly enabled by caller
# Example: LOGGING_ENV_AUTO=1 before sourcing or after.
if [[ "${LOGGING_ENV_AUTO:-0}" = "1" ]]; then
    log_init
    install_logging_traps
fi
