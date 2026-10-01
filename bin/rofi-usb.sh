#!/usr/bin/env bash
# Select removable USB devices and mount or unmount them through udisks2.

set -o errexit -o nounset -o pipefail

BSPWM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bspwm"
ROFI_THEME="$BSPWM_CONFIG_DIR/rofi/themes/usb.rasi"

notify() {
    local title=$1
    local message=$2
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$title" "$message"
    fi
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        notify "USB" "Programm nicht gefunden: $1"
        printf 'rofi-usb: program not found: %s\n' "$1" >&2
        return 1
    fi
}

block_devices_json() {
    if [[ -n ${ROFI_USB_LSBLK_JSON:-} ]]; then
        cat -- "$ROFI_USB_LSBLK_JSON"
        return
    fi
    lsblk --json --paths \
        --output PATH,TYPE,SIZE,MOUNTPOINTS,RM,TRAN,MODEL
}

list_usb_devices() {
    local mode=$1
    block_devices_json | jq -r --arg mode "$mode" '
        def devices($parent_usb; $parent_model):
            . as $device
            | ($parent_usb or (.rm == true) or (.tran == "usb")) as $usb
            | (.model // $parent_model // "") as $model
            | {
                path: .path,
                type: .type,
                size: (.size // "?"),
                mountpoints: (.mountpoints // []),
                model: $model,
                child_count: ((.children // []) | length),
                usb: $usb
              },
              (.children[]? | devices($usb; $model));

        .blockdevices[]
        | devices(false; "")
        | select(.usb)
        | select((.type == "part") or (.type == "disk" and .child_count == 0))
        | . + {
            mounted: ([.mountpoints[]? | select((. // "") != "")] | length > 0),
            mountpoint_text: ([.mountpoints[]? | select((. // "") != "")] | join(", "))
          }
        | select(if $mode == "mount" then (.mounted | not) else .mounted end)
        | [.path, .size, .mountpoint_text, .model]
        | @tsv
    '
}

select_entry() {
    local prompt=$1
    shift
    local selection entry

    selection="$(
        printf '%s\n' "$@" | rofi \
            -no-config \
            -dmenu \
            -i \
            -p "$prompt" \
            -theme "$ROFI_THEME"
    )" || return 1

    for entry in "$@"; do
        if [[ $selection == "$entry" ]]; then
            printf '%s\n' "$selection"
            return 0
        fi
    done
    return 1
}

select_device() {
    local mode=$1
    local prompt=$2
    local -a entries
    mapfile -t entries < <(list_usb_devices "$mode")

    if ((${#entries[@]} == 0)); then
        if [[ $mode == mount ]]; then
            notify "USB" "Kein nicht eingebundenes USB-Laufwerk gefunden."
        else
            notify "USB" "Kein eingebundenes USB-Laufwerk gefunden."
        fi
        return 1
    fi

    select_entry "$prompt" "${entries[@]}"
}

mount_device() {
    local selection path output
    selection=$(select_device mount "USB einbinden") || return 0
    path=${selection%%$'\t'*}

    if output=$(udisksctl mount --no-user-interaction --block-device "$path" 2>&1); then
        notify "USB eingebunden" "$output"
    else
        notify "USB konnte nicht eingebunden werden" "$output"
        return 1
    fi
}

unmount_device() {
    local selection path output
    selection=$(select_device unmount "USB aushängen") || return 0
    path=${selection%%$'\t'*}

    if output=$(udisksctl unmount --no-user-interaction --block-device "$path" 2>&1); then
        notify "USB ausgehängt" "$output"
    else
        notify "USB konnte nicht ausgehängt werden" "$output"
        return 1
    fi
}

unmount_all() {
    local answer entry path output
    local -a entries failures
    mapfile -t entries < <(list_usb_devices unmount)

    if ((${#entries[@]} == 0)); then
        notify "USB" "Kein eingebundenes USB-Laufwerk gefunden."
        return 0
    fi

    answer=$(select_entry "Alle USB-Laufwerke aushängen?" \
        "Abbrechen" "Alle aushängen") || return 0
    [[ $answer == "Alle aushängen" ]] || return 0

    failures=()
    for entry in "${entries[@]}"; do
        path=${entry%%$'\t'*}
        if ! output=$(udisksctl unmount --no-user-interaction \
            --block-device "$path" 2>&1); then
            failures+=("$path: $output")
        fi
    done

    if ((${#failures[@]} == 0)); then
        notify "USB" "Alle USB-Laufwerke wurden ausgehängt."
    else
        notify "USB – Fehler" "$(printf '%s\n' "${failures[@]}")"
        return 1
    fi
}

main() {
    require_command jq

    case ${1:-} in
    --list-mountable)
        list_usb_devices mount
        return
        ;;
    --list-mounted)
        list_usb_devices unmount
        return
        ;;
    "")
        require_command lsblk
        require_command rofi
        require_command udisksctl
        ;;
    *)
        printf 'Usage: %s [--list-mountable|--list-mounted]\n' "${0##*/}" >&2
        return 2
        ;;
    esac

    local action
    action=$(select_entry "USB" \
        "Einbinden" "Aushängen" "Alle aushängen") || return 0

    case $action in
    "Einbinden") mount_device ;;
    "Aushängen") unmount_device ;;
    "Alle aushängen") unmount_all ;;
    esac
}

main "$@"
