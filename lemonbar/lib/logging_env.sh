# shellcheck shell=bash

# Minimal logging shared by the lemonbar scripts.
# Every message is appended to $TMPDIR/lemonbar.log and written to stderr.
if [[ ${LEMONBAR_LOGGING_LOADED:-0} == 1 ]]; then
    return 0
fi
LEMONBAR_LOGGING_LOADED=1

LOG_FILE="${TMPDIR:-/tmp}/lemonbar.log"
export LOG_FILE

LOG_INFO_ENABLED="${LOG_INFO_ENABLED:-0}"
export LOG_INFO_ENABLED

log_write() {
    local level="ERROR"

    if (($# > 0)); then
        level=$1
        shift
    fi

    local line message
    message="$*"
    message=${message//$'\n'/\\n}
    printf -v line '%(%F %T)T\t%s\t%s: %s\n' \
        -1 "${0##*/}" "$level" "$message"

    # Logging must never terminate the calling script.
    printf '%s' "$line" 2>/dev/null >>"$LOG_FILE" || true
    printf '%s' "$line" >&2 2>/dev/null || true
}

log_info() {
    [[ "$LOG_INFO_ENABLED" == "1" ]] || return 0
    log_write "INFO" "$@"
}

log_error() {
    log_write "ERROR" "$@"
}
