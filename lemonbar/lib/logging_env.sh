# shellcheck shell=bash

# Minimal logging shared by the lemonbar scripts.
# Every message is appended to $TMPDIR/lemonbar.log and written to stderr.
LOG_FILE="${TMPDIR:-/tmp}/lemonbar.log"
export LOG_FILE

log_write() {
    local level="$1"
    shift

    local line
    printf -v line '%(%F %T)T\t%s\t%s: %s\n' \
        -1 "${0##*/}" "$level" "$*"

    printf '%s' "$line" >>"$LOG_FILE"
    printf '%s' "$line" >&2
}

log_info() {
    log_write "INFO" "$@"
}

log_error() {
    log_write "ERROR" "$@"
}
