#!/usr/bin/env bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace # Trace the execution of the script (debug)
fi

set -o errexit  # Exit on most errors (see the manual)
set -o nounset  # Disallow expansion of unset variables
set -o pipefail # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
set -o errtrace # Ensure the error trap handler is inherited

source "$LEMONDIR/config.sh"

if ! declare -F log_error >/dev/null; then
    printf 'logging bootstrap not loaded: %s\n' "${BASH_ENV:-unset}" >&2
    exit 1
fi

# Check parameter count.
if [[ $# -ne 1 || ! $1 =~ ^[0-9]+$ ]]; then
    echo "Usage: $0 <sighandler_pid>" >&2
    exit 2
fi

sighandler_pid=$1

# shellcheck disable=SC2154
title_cache="$tmp_dir/lemonbar_title.cache"
title_cache_tmp="$title_cache.${BASHPID}"
xtmon_pid=""

# DESC: Stop the title watcher and remove title cache files
# ARGS: None
# OUTS: None
trap_cleanup() {
    trap - EXIT INT TERM QUIT HUP

    if [[ "${xtmon_pid:-}" =~ ^[0-9]+$ ]]; then
        kill -TERM "$xtmon_pid" 2>/dev/null || true
        wait "$xtmon_pid" 2>/dev/null || true
        xtmon_pid=""
    fi

    rm -f -- "$title_cache" "$title_cache_tmp"
}

trap 'trap_cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 0' QUIT HUP

if kill -0 "$sighandler_pid" 2>/dev/null; then
    log_info "sighandler_pid is valid: PID=" "$sighandler_pid"
else
    log_error "sighandler_pid is invalid: PID=" "$sighandler_pid"
    exit 1
fi

# Publish one formatted title and notify the renderer.
publish_title() {
    local title="${1:0:TITLE_MAX_LENGHT}"

    if ! printf '%s\n' \
        "%{B$COLOR_DEFAULT_BG}%{F$COLOR_FREE_FG}%{+u}$PADDING$title$PADDING%{-u}%{F-}%{B-}" \
        >"$title_cache_tmp"; then
        log_error "cannot write title cache: $title_cache_tmp"
        return 1
    fi

    if ! mv -f -- "$title_cache_tmp" "$title_cache"; then
        log_error "cannot publish title cache: $title_cache"
        return 1
    fi

    if ! kill -s "$SIGNAL_TITLE" "$sighandler_pid" 2>/dev/null; then
        log_error "sighandler not running: pid=$sighandler_pid"
        return 1
    fi
}

coproc XTMON {
    exec "$LEMONDIR/xtmon.sh"
}

# Bash creates XTMON_PID dynamically for the named coprocess.
# shellcheck disable=SC2153
xtmon_pid=$XTMON_PID
xtmon_fd=${XTMON[0]}

while IFS= read -r line <&"$xtmon_fd"; do
    publish_title "$line"
done

if wait "$xtmon_pid"; then
    watcher_rc=0
else
    watcher_rc=$?
fi
xtmon_pid=""

# A title watcher is expected to live as long as the signal handler.
if kill -0 "$sighandler_pid" 2>/dev/null; then
    log_error "title watcher stopped unexpectedly: rc=$watcher_rc"
    ((watcher_rc != 0)) || watcher_rc=1
    exit "$watcher_rc"
fi
