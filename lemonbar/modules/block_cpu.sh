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

stat_file=${CPU_STAT_FILE:-/proc/stat}
state_file=${CPU_STATE_FILE:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/lemonbar_cpu_${UID}.state}
state_max_age=${CPU_STATE_MAX_AGE:-15}

if [[ ! $state_max_age =~ ^[0-9]+$ ]] || ((state_max_age == 0)); then
    log_error "invalid CPU_STATE_MAX_AGE: $state_max_age"
    exit 1
fi

# The aggregate cpu line contains cumulative time counters since boot.
if ! read -r label user nice system idle iowait irq softirq steal _ <"$stat_file" ||
    [[ $label != cpu ]] ||
    [[ ! $user =~ ^[0-9]+$ || ! $nice =~ ^[0-9]+$ ||
        ! $system =~ ^[0-9]+$ || ! $idle =~ ^[0-9]+$ ||
        ! $iowait =~ ^[0-9]+$ || ! $irq =~ ^[0-9]+$ ||
        ! $softirq =~ ^[0-9]+$ || ! $steal =~ ^[0-9]+$ ]]; then
    log_error "invalid aggregate CPU data: $stat_file"
    exit 1
fi

total=$((user + nice + system + idle + iowait + irq + softirq + steal))
idle_total=$((idle + iowait))
usage_tenths=0

# Calculate utilization from the difference to the preceding scheduler update.
if [[ -r $state_file ]] &&
    read -r previous_total previous_idle previous_time <"$state_file" &&
    [[ $previous_total =~ ^[0-9]+$ && $previous_idle =~ ^[0-9]+$ &&
        $previous_time =~ ^[0-9]+$ ]] &&
    ((total > previous_total && idle_total >= previous_idle &&
        EPOCHSECONDS >= previous_time &&
        EPOCHSECONDS - previous_time <= state_max_age)); then
    total_delta=$((total - previous_total))
    idle_delta=$((idle_total - previous_idle))

    if ((idle_delta <= total_delta)); then
        active_delta=$((total_delta - idle_delta))
        usage_tenths=$(((active_delta * 1000 + total_delta / 2) / total_delta))
        ((usage_tenths > 1000)) && usage_tenths=1000
    fi
fi

if ! printf '%s %s %s\n' "$total" "$idle_total" "$EPOCHSECONDS" >"$state_file"; then
    log_error "could not update CPU state: $state_file"
fi

printf -v usage '%d.%d' "$((usage_tenths / 10))" "$((usage_tenths % 10))"

icon=""
cpu_action=$(lemonbar_action bash "$LEMONDIR/lib/click_action.sh" terminal btop)

printf "%s" "%{A1:${cpu_action}:}%{B$COLOR_DEFAULT_BG}%{F$COLOR_SYS_FG}%{+u} $icon ${usage}% %{-u}%{F-}%{B-}%{A}"
