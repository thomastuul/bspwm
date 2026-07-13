#!/usr/bin/env bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace # Trace the execution of the script (debug)
fi

set -o errexit  # Exit on most errors (see the manual)
set -o nounset  # Disallow expansion of unset variables
set -o pipefail # Use last non-zero exit code in a pipeline
set -o errtrace # Ensure the error trap handler is inherited

# shellcheck disable=SC1091
source "$LEMONDIR/config.sh"
# shellcheck source=../lib/lemonbar_action.sh
source "$LEMONDIR/lib/lemonbar_action.sh"
# shellcheck disable=SC1090
if [[ -n ${BASH_ENV:-} && -r $BASH_ENV ]]; then
    # shellcheck source=../lib/logging_env.sh
    source "$BASH_ENV"
else
    exit 1
fi

declare -a icons=('' '' '' '' '' '' '' '' '')
declare -a report_items=()

set_num=false
lemonbar_output=""
focused_layout=""
monitor_focused=false
desktop_index=0

workspace_colors() {
    case $1 in
    O)
        FG=$COLOR_FOCUSED_OCCUPIED_FG
        BG=$COLOR_FOCUSED_OCCUPIED_BG
        ;;
    o)
        FG=$COLOR_OCCUPIED_FG
        BG=$COLOR_OCCUPIED_BG
        ;;
    F)
        FG=$COLOR_FOCUSED_FREE_FG
        BG=$COLOR_FOCUSED_FREE_BG
        ;;
    f)
        FG=$COLOR_FREE_FG
        BG=$COLOR_FREE_BG
        ;;
    U)
        FG=$COLOR_FOCUSED_URGENT_FG
        BG=$COLOR_FOCUSED_URGENT_BG
        ;;
    u)
        FG=$COLOR_URGENT_FG
        BG=$COLOR_URGENT_BG
        ;;
    esac
}

report=$(bspc subscribe report --count 1)
# This setup uses "W" as bspwm's status prefix for report lines.
report=${report#W}
IFS=: read -r -a report_items <<<"$report"

for item in "${report_items[@]}"; do
    type=${item:0:1}
    value=${item:1}

    case $type in
    M | m)
        monitor_focused=false
        if [[ $type == M ]]; then
            monitor_focused=true
        fi
        desktop_index=0
        ;;
    O | o | F | f | U | u)
        if [[ $monitor_focused != true ]]; then
            continue
        fi

        workspace_colors "$type"
        callback=$(lemonbar_action \
            bash "$LEMONDIR/lib/click_action.sh" workspace "$value")

        if [[ $set_num == false && $desktop_index -lt ${#icons[@]} ]]; then
            tag_name=${icons[$desktop_index]}
        else
            tag_name=$value
        fi

        lemonbar_output+="%{F${FG}}%{B${BG}}%{U${COLOR_FOREGROUND}}%{+u}"
        lemonbar_output+="%{A1:${callback}:}${PADDING}${tag_name}${PADDING}%{A}"
        lemonbar_output+="%{B-}%{F-}%{-u}"
        ((++desktop_index))
        ;;
    L)
        if [[ $monitor_focused == true ]]; then
            focused_layout=$value
        fi
        ;;
    esac
done

case $focused_layout in
T) layout="[TILED]" ;;
M) layout="[MONOCLE]" ;;
*) layout="[UNKNOWN]" ;;
esac

lemonbar_output+="%{F$COLOR_FREE_FG}%{B$COLOR_DEFAULT_BG}"
lemonbar_output+="${PADDING}${layout}${PADDING}%{B-}%{F-}"
printf '%s' "$lemonbar_output"
