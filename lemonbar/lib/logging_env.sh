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
    LOG_FILE="$TMPDIR/lemonbar_default.$(date +'%F_%H-%M-%S').log"
fi
export LOG_FILE

# ---- internal helpers --------------------------------------------------------

# Protokolliert Fehler, verhindert Abbruch unter 'set -e', liefert immer 0 zurück.
call_or_log() {
    # Aufruf: call_or_log <cmd> [args...]
    if ! "$@"; then
        local rc=$?
        # "$*" = vollständiger Befehl zur Nachvollziehbarkeit
        log_warn "cmd_failed" "rc=$rc" "cmd=$*"
        return 0
    fi
}

# Speziell für Signale, damit 'kill' nie das Skript beendet
kill_or_log() {
    # Aufruf: kill_or_log <signal> <pid>
    local sig=$1 pid=$2
    if ! kill -s "$sig" "$pid" 2>/dev/null; then
        local rc=$?
        log_warn "kill_failed" "rc=$rc" "sig=$sig" "pid=$pid"
        return 0
    fi
}

_ts() {
    # 24h timestamp
    date +'%F %T'
}

# DESC: Append a handler to an existing trap
# ARGS: $1 = signal (e.g. EXIT, ERR, INT), $2+ = handler
_trap_add() {
    local sig add existing cmd _pf

    [[ $# -ge 2 ]] || return 2
    sig=$1
    shift
    add=$*

    # Variante mit lokalem pipefail-Bypass
    _pf=$(set -o | awk '/pipefail/ {print $2}')
    set +o pipefail
    existing="$(trap -p "$sig" | awk -F"'" 'NR==1{print $2}')"
    [[ "$_pf" == on ]] && set -o pipefail

    if [[ -n "${existing:-}" ]]; then
        cmd="${existing}; ${add}"
    else
        cmd="${add}"
    fi

    trap -- "$cmd" "$sig"
}

# ---- public API --------------------------------------------------------------

# Initialize logging. Opens FD 3 for appends. Idempotent.
log_init() {
    # Create parent dir if needed
    mkdir -p -- "$TMPDIR"

    # Touch file before opening FD to avoid race warnings
    : >>"$LOG_FILE"

    # Open append FD if not already open
    if ! { true >&3; } 2>/dev/null; then
        # shellcheck disable=SC3033
        exec 3>>"$LOG_FILE"
    fi
}

# Generic writer
_log_write() {
    # $1 level, $2 message, $3 rc
    local lvl msg rc
    lvl="$1"
    msg="$2"
    rc="${3:-}"

    # Ensure FD 3 exists if someone forgot log_init
    if ! { true >&3; } 2>/dev/null; then
        log_init
    fi

    printf '%s\t%s\t%s\t%s\n' "$(_ts)" "$script_name" "$lvl: $msg" "$rc" >&3
}

# Info message
log_info() {
    case "${LOG_INFO:-0}" in
    1 | yes | true | on) _log_write "INFO" "${1:-}" "${2:-}" ;;
    *) : ;; # quiet
    esac
}

# Error message with line number and return code
log_err() {
    # $1 lineno, [$2 rc]
    local ln rc
    ln="${1:-0}"
    rc="${2:-1}"
    _log_write "ERROR" "line=$ln" "return code=$rc"
}

_trap_on_err() {
    local ec=$?
    local ln="${BASH_LINENO[0]:-$LINENO}"
    if ((ec < 128)); then
        log_err "$ln" "$ec"
    fi
    return "$ec"
}

_trap_on_exit() {
    local ec=$?
    local ln="${BASH_LINENO[1]:-$LINENO}"
    case "${LOG_INFO:-0}" in
    1 | yes | true | on) log_info "line=$ln" "exit rc=$ec" ;;
    esac
    # Close FD 3 if it exists; ignore errors
    { true >&3; } 2>/dev/null && exec 3>&- || true
    exit "$ec"
}

# Install ERR/EXIT traps alongside any existing handlers.
install_logging_traps() {
    # neu: Signal-bedingte Exits (>=128) auslassen und bessere Zeilenermittlung
    # shellcheck disable=SC2016
    _trap_add ERR _trap_on_err

    # EXIT: log final rc and close FD 3 if open
    # shellcheck disable=SC2016
    _trap_add EXIT _trap_on_exit
}

# Optional automatic bootstrap if explicitly enabled by caller
# Example: LOGGING_ENV_AUTO=1 before sourcing or after.
if [[ "${LOGGING_ENV_AUTO:-0}" = "1" ]]; then
    log_init
    install_logging_traps
fi
