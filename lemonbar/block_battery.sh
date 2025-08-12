#!/usr/bin/env bash
# Battery block for lemonbar (bspwm panel)
# Reads /sys/class/power_supply for battery info and prints a formatted line.

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace
fi

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

# shellcheck disable=SC1091
source "${LEMONDIR}/config.sh"

# Colors (with sensible fallbacks)
BG_COLOR="${COLOR_DEFAULT_BG:-#000000}"
FG_COLOR="${COLOR_BATTERY_FG:-${COLOR_DEFAULT_FG:-#FFFFFF}}"
WARN_COLOR="${COLOR_BATTERY_WARN_FG:-#ffcc00}"
CRIT_COLOR="${COLOR_BATTERY_CRIT_FG:-#ff5555}"
CHAR_COLOR_CHARGING="${COLOR_BATTERY_CHARGING_FG:-${FG_COLOR}}"

# Icons (Font Awesome / Nerd Font)
ICON_EMPTY=""
ICON_QUARTER=""
ICON_HALF=""
ICON_THREEQ=""
ICON_FULL=""
ICON_PLUG=""
ICON_BOLT=""

# Find battery directories
BAT_DIRS=( /sys/class/power_supply/BAT* )
if (( ${#BAT_DIRS[@]} == 0 )); then
    # No battery found; likely desktop: show AC
    printf "%s\n" "%{B$BG_COLOR}%{F$FG_COLOR}%{+u} $ICON_PLUG AC %{-u}%{F-}%{B-}"
    exit 0
fi

# Compute average percentage and combined status
total_pct=0
charging=false
full=true
discharging=false

for bd in "${BAT_DIRS[@]}"; do
    if [[ -r "${bd}/capacity" ]]; then
        read -r c < "${bd}/capacity"
    elif [[ -r "${bd}/charge_now" && -r "${bd}/charge_full" ]]; then
        read -r now < "${bd}/charge_now"
        read -r full_chg < "${bd}/charge_full"
        # Avoid division by zero
        (( full_chg == 0 )) && full_chg=1
        c=$(( now * 100 / full_chg ))
    else
        c=0
    fi
    total_pct=$(( total_pct + c ))

    if [[ -r "${bd}/status" ]]; then
        read -r st < "${bd}/status"
        case "$st" in
            [Cc]harging) charging=true; full=false ;;
            [Ff]ull) full=true ;;
            [Dd]ischarging) discharging=true; full=false ;;
            *) ;;
        esac
    fi
done

pct=$(( total_pct / ${#BAT_DIRS[@]} ))

# Choose icon based on percentage
battery_icon="$ICON_EMPTY"
if   (( pct >= 95 )); then battery_icon="$ICON_FULL"
elif (( pct >= 75 )); then battery_icon="$ICON_THREEQ"
elif (( pct >= 50 )); then battery_icon="$ICON_HALF"
elif (( pct >= 25 )); then battery_icon="$ICON_QUARTER"
else                       battery_icon="$ICON_EMPTY"
fi

# Choose color based on thresholds and charging state
color="$FG_COLOR"
if "$charging"; then
    color="$CHAR_COLOR_CHARGING"
elif (( pct <= 10 )); then
    color="$CRIT_COLOR"
elif (( pct <= 20 )); then
    color="$WARN_COLOR"
fi

# Status markers
status_mark=""
if "$charging"; then
    status_mark="$ICON_BOLT"
elif "$full"; then
    status_mark="$ICON_PLUG"
fi

printf "%s\n" "%{B$BG_COLOR}%{F$color}%{+u} $battery_icon ${pct}%% ${status_mark} %{-u}%{F-}%{B-}"
