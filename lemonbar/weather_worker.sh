#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ ${DEBUG-} =~ ^(1|yes|true)$ ]]; then
    set -o xtrace
fi

# shellcheck disable=SC1090
if [[ -n "${BASH_ENV:-}" && -r "$BASH_ENV" ]]; then
    # shellcheck source=lib/logging_env.sh
    source "$BASH_ENV"
else
    printf 'logging_env.sh not found: %s\n' "${BASH_ENV:-unset}" >&2
    exit 1
fi

if [[ $# -ne 1 || ! $1 =~ ^[0-9]+$ ]]; then
    printf 'Usage: %s <sighandler_pid>\n' "$0" >&2
    exit 2
fi

sighandler_pid=$1
cache_root="${XDG_CACHE_HOME:-$HOME/.cache}"
weather_cache_dir="${WEATHERREPORT:-$cache_root/weather}"
display_cache="$weather_cache_dir/lemonbar.cache"
display_cache_tmp="$display_cache.${BASHPID}"

cleanup() {
    trap - EXIT INT TERM HUP
    rm -f -- "$display_cache_tmp"
}

trap cleanup EXIT
trap 'exit 0' INT TERM HUP

refresh_weather() {
    local output

    if ! output=$("$LEMONDIR/modules/block_weather.sh"); then
        log_error "weather refresh failed"
        return 0
    fi

    [[ -n $output ]] || return 0

    mkdir -p -- "$weather_cache_dir"
    printf '%s\n' "$output" >"$display_cache_tmp"
    mv -f -- "$display_cache_tmp" "$display_cache"
}

prefetch_weather_image() {
    if ! "$LEMONDIR/modules/block_weather.sh" --prefetch-image; then
        log_error "weather image prefetch failed"
    fi
}

while kill -0 "$sighandler_pid" 2>/dev/null; do
    refresh_weather
    prefetch_weather_image

    # Check the parent every second while keeping a one-minute refresh cycle.
    for ((second = 0; second < 60; second++)); do
        kill -0 "$sighandler_pid" 2>/dev/null || exit 0
        sleep 1
    done
done
