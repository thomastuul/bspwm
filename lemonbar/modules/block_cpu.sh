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

# shellcheck disable=SC1091
source "$LEMONDIR/config.sh"
# shellcheck source=../lib/lemonbar_action.sh
source "$LEMONDIR/lib/lemonbar_action.sh"
# shellcheck disable=SC1090
if [[ -n "${BASH_ENV:-}" && -r "$BASH_ENV" ]]; then
    # shellcheck source=../lib/logging_env.sh
    source "$BASH_ENV"
else
    exit 1
fi

read -r load_average _ </proc/loadavg

# CPU directories correspond to the logical processors reported by nproc --all.
shopt -s nullglob
cpu_directories=(/sys/devices/system/cpu/cpu[0-9]*)
shopt -u nullglob
cpu_count=${#cpu_directories[@]}

if ((cpu_count == 0)); then
    log_error "no logical CPUs found"
    exit 1
fi

# Convert the load average to thousandths and calculate tenths of a percent.
load_whole=${load_average%%.*}
load_fraction=${load_average#*.}000
load_thousandths=$((10#$load_whole * 1000 + 10#${load_fraction:0:3}))
load_tenths=$((load_thousandths / cpu_count))
load_remainder=$((load_thousandths % cpu_count))

# Match printf's round-half-to-even behavior at exactly half a tenth.
if ((load_remainder * 2 > cpu_count ||
    (load_remainder * 2 == cpu_count && load_tenths % 2 != 0))); then
    ((++load_tenths))
fi

printf -v load '%d.%d' "$((load_tenths / 10))" "$((load_tenths % 10))"

icon=""
cpu_action=$(lemonbar_action bash "$LEMONDIR/lib/click_action.sh" terminal btop)

printf "%s" "%{A1:${cpu_action}:}%{B$COLOR_DEFAULT_BG}%{F$COLOR_SYS_FG}%{+u} $icon ${load}% %{-u}%{F-}%{B-}%{A}"
