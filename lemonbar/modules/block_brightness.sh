#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

# Enable xtrace for explicit debug runs.
if [[ ${DEBUG-} =~ ^(1|yes|true)$ ]]; then
    set -o xtrace
fi

# shellcheck disable=SC1091
source "$LEMONDIR/config.sh"
# shellcheck disable=SC1090
if [[ -n "${BASH_ENV:-}" && -r "$BASH_ENV" ]]; then
    # shellcheck source=../lib/logging_env.sh
    source "$BASH_ENV"
else
    printf 'BASH_ENV not found: %s\n' "${BASH_ENV:-unset}" >&2
    exit 1
fi

die() {
    printf 'block_brightness: %s\n' "$*" >&2
    exit 1
}

if [[ $# -ne 2 ]]; then
    die "expected <change> <sighandler_pid>"
fi

change_level=$1
sighandler_pid=$2

[[ $change_level == " " || $change_level == "+" || $change_level == "-" ]] ||
    die "invalid change: $change_level"
[[ $sighandler_pid =~ ^[0-9]+$ ]] ||
    die "invalid sighandler PID: $sighandler_pid"

brightness_step="${BRIGHTNESS_STEP:-5}"
brightness_min="${BRIGHTNESS_MIN:-5}"
brightness_max="${BRIGHTNESS_MAX:-100}"

[[ $brightness_step =~ ^[1-9][0-9]*$ ]] ||
    die "invalid BRIGHTNESS_STEP: $brightness_step"
[[ $brightness_min =~ ^[0-9]+$ ]] ||
    die "invalid BRIGHTNESS_MIN: $brightness_min"
[[ $brightness_max =~ ^[0-9]+$ ]] ||
    die "invalid BRIGHTNESS_MAX: $brightness_max"
((brightness_min <= brightness_max)) ||
    die "BRIGHTNESS_MIN must not exceed BRIGHTNESS_MAX"

# Allow an explicit output and otherwise select the first active monitor.
connection="${BRIGHTNESS_OUTPUT:-}"
if [[ -z $connection ]]; then
    connection=$(
        xrandr --query |
            awk '
                $2 == "connected" {
                    for (i = 3; i <= NF; i++) {
                        if ($i ~ /^[0-9]+x[0-9]+[+][0-9]+[+][0-9]+/) {
                            if (!found) {
                                print $1
                                found = 1
                            }
                        }
                    }
                }
            '
    )
fi
[[ -n $connection ]] || die "no active monitor found"

brightness=$(
    xrandr --verbose --current |
        awk -v output="$connection" '
            $1 == output && $2 == "connected" {
                active = 1
                next
            }
            active && $1 == "Brightness:" && !found {
                print $2
                found = 1
            }
            active && $0 !~ /^[[:space:]]/ {
                active = 0
            }
        '
)
[[ $brightness =~ ^[0-9]+([.][0-9]+)?$ ]] ||
    die "invalid brightness for $connection: ${brightness:-missing}"

brightness_int=$(
    awk -v value="$brightness" 'BEGIN { printf "%.0f", value * 100 }'
)

set_brightness() {
    local target=$1 value

    ((target < brightness_min)) && target=$brightness_min
    ((target > brightness_max)) && target=$brightness_max

    value=$(
        awk -v percent="$target" 'BEGIN { printf "%.2f", percent / 100 }'
    )

    xrandr --output "$connection" --brightness "$value"
    brightness_int=$target
}

case "$change_level" in
"+")
    set_brightness "$((brightness_int + brightness_step))"
    ;;
"-")
    set_brightness "$((brightness_int - brightness_step))"
    ;;
" ")
    ;;
esac

inc="kill -s SIGRTMIN+7 $sighandler_pid"
dec="kill -s SIGRTMIN+8 $sighandler_pid"
icon=""

printf '%s' \
    "%{A4:${inc}:}%{A5:${dec}:}%{B$COLOR_DEFAULT_BG}%{F$COLOR_MONITOR_FG}%{+u} $icon ${brightness_int}% %{-u}%{F-}%{B-}%{A}%{A}"
