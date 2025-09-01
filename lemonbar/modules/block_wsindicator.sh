#!/usr/bin/env bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

set -o errexit      # Exit on most errors (see the manual)
set -o nounset      # Disallow expansion of unset variables
set -o pipefail     # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
set -o errtrace     # Ensure the error trap handler is inherited

# shellcheck disable=SC1091
source "$LEMONDIR/config.sh"

FG=$COLOR_DEFAULT_FG
BG=$COLOR_DEFAULT_BG
UL=$COLOR_FOREGROUND

declare -a icons=('' '' '' '' '' '' '' '' '');
set_num=false

bspc subscribe report --count 1 | while read -r line; do
    if [[ $line =~ ^WM[[:space:]]*([^:]+):(.*)$ ]]; then
        workspace_index="${BASH_REMATCH[1]}"
        workspace_info="${BASH_REMATCH[2]}"

        IFS=, read -r -a monitors <<< "$workspace_index"

        lemonbar_output=""
        for monitor in "${monitors[@]}"; do
            workspace_names=$(bspc query -D -m "$monitor" --names)
            IFS=: read -ra ws_array <<< "$workspace_info"
            k=0
            for name in $workspace_names; do
                CALLBACK="bspc desktop -f ${name}"
                if [[ "$set_num" == false ]]; then
                    tag_name="${icons[$k]}"
                else
                    tag_name=${name}
                fi
                case "${ws_array[$k]}" in
                    # Occupied focused desktop
                    O*) FG=$COLOR_FOCUSED_OCCUPIED_FG; BG=$COLOR_FOCUSED_OCCUPIED_BG; UL=$COLOR_FOREGROUND ;;
                    # Occupied unfocused desktop
                    o*) FG=$COLOR_OCCUPIED_FG; BG=$COLOR_OCCUPIED_BG; UL=$COLOR_FOREGROUND ;;
                    # Free focused desktop
                    F*) FG=$COLOR_FOCUSED_FREE_FG; BG=$COLOR_FOCUSED_FREE_BG; UL=$COLOR_FOREGROUND ;;
                    # Free unfocused desktop
                    f*) FG=$COLOR_FREE_FG; BG=$COLOR_FREE_BG; UL=$COLOR_FOREGROUND ;;
                    # Urgent focused desktop
                    U*) FG=$COLOR_FOCUSED_URGENT_FG; BG=$COLOR_FOCUSED_URGENT_BG; UL=$COLOR_FOREGROUND ;;
                    # Urgent unfocused desktop
                    u*) FG=$COLOR_URGENT_FG; BG=$COLOR_URGENT_BG; UL=$COLOR_FOREGROUND ;;
                esac
                lemonbar_output+="%{F${FG}}%{B${BG}}%{U${UL}}%{+u}%{A1:${CALLBACK}:}$PADDING${tag_name}$PADDING%{A}%{B-}%{F-}%{-u}"
                (( ++k ))
            done
        done
        case "${ws_array[$k]}" in
            LT) layout="[TILED]" ;;
            LM) layout="[MONOCLE]" ;;
             *) layout="[FULLSCREEN]" ;;
        esac
        lemonbar_output+="%{F$COLOR_FREE_FG}%{B$COLOR_DEFAULT_BG}$PADDING${layout}$PADDING%{B-}%{F-}"
        printf "%s" "$lemonbar_output"
    fi
done
