#!/usr/bin/env bash
# Select a monitor layout without evaluating generated shell commands.

set -o errexit -o nounset -o pipefail

BSPWM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bspwm"
ROFI_THEME="$BSPWM_CONFIG_DIR/rofi/themes/monitor.rasi"

monitor_query() {
    if [[ -n ${ROFI_MONITOR_XRANDR_OUTPUT:-} ]]; then
        cat -- "$ROFI_MONITOR_XRANDR_OUTPUT"
        return
    fi
    xrandr --query
}

connected_monitors() {
    monitor_query | awk '$2 == "connected" {print $1}'
}

build_layouts() {
    labels=("Abbrechen")
    kinds=(cancel)
    first_monitors=("")
    second_monitors=("")

    local monitor left right
    for monitor in "${monitors[@]}"; do
        labels+=("Nur $monitor")
        kinds+=(only)
        first_monitors+=("$monitor")
        second_monitors+=("")
    done

    local first_index second_index
    for ((first_index = 0; first_index < ${#monitors[@]}; first_index++)); do
        for ((second_index = first_index + 1; second_index < ${#monitors[@]}; second_index++)); do
            left=${monitors[first_index]}
            right=${monitors[second_index]}

            labels+=("Erweitert: $left links, $right rechts")
            kinds+=(extend)
            first_monitors+=("$left")
            second_monitors+=("$right")

            labels+=("Erweitert: $right links, $left rechts")
            kinds+=(extend)
            first_monitors+=("$right")
            second_monitors+=("$left")

            labels+=("Spiegeln: $left und $right")
            kinds+=(mirror)
            first_monitors+=("$left")
            second_monitors+=("$right")
        done
    done
}

select_layout() {
    local selection label index
    selection="$(
        printf '%s\n' "${labels[@]}" | rofi \
            -no-config \
            -dmenu \
            -i \
            -no-custom \
            -p "Monitore" \
            -theme "$ROFI_THEME"
    )" || return 1

    for index in "${!labels[@]}"; do
        label=${labels[index]}
        if [[ $selection == "$label" ]]; then
            printf '%s\n' "$index"
            return 0
        fi
    done
    return 1
}

apply_layout() {
    local index=$1
    local kind=${kinds[index]}
    local first=${first_monitors[index]}
    local second=${second_monitors[index]}
    local monitor
    local -a command=(xrandr)

    case $kind in
    cancel)
        return 0
        ;;
    only)
        command+=(--output "$first" --auto)
        for monitor in "${monitors[@]}"; do
            [[ $monitor == "$first" ]] || command+=(--output "$monitor" --off)
        done
        ;;
    extend)
        command+=(--output "$first" --auto \
            --output "$second" --auto --right-of "$first")
        for monitor in "${monitors[@]}"; do
            [[ $monitor == "$first" || $monitor == "$second" ]] || \
                command+=(--output "$monitor" --off)
        done
        ;;
    mirror)
        command+=(--output "$first" --auto \
            --output "$second" --auto --same-as "$first")
        for monitor in "${monitors[@]}"; do
            [[ $monitor == "$first" || $monitor == "$second" ]] || \
                command+=(--output "$monitor" --off)
        done
        ;;
    esac

    "${command[@]}"
}

main() {
    command -v xrandr >/dev/null 2>&1 || return 1

    mapfile -t monitors < <(connected_monitors)
    if ((${#monitors[@]} == 0)); then
        command -v notify-send >/dev/null 2>&1 && \
            notify-send "Monitore" "Keine verbundenen Monitore gefunden."
        return 1
    fi
    build_layouts

    if [[ ${1:-} == --list ]]; then
        printf '%s\n' "${labels[@]}"
        return 0
    fi
    if [[ $# -ne 0 ]]; then
        printf 'Usage: %s [--list]\n' "${0##*/}" >&2
        return 2
    fi

    command -v rofi >/dev/null 2>&1 || return 1
    local selection
    selection=$(select_layout) || return 0
    apply_layout "$selection"
}

main "$@"
