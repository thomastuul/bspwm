# shellcheck shell=bash

# Minimal logging shared by the lemonbar scripts.
# Every message is appended to the current runtime directory and written to
# stderr. start.sh creates and exports tmp_dir before sourcing this file.
: "${tmp_dir:?tmp_dir must be set before sourcing logging_env.sh}"
LOG_FILE="$tmp_dir/lemonbar.log"
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
