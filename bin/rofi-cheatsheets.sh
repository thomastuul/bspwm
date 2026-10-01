#!/usr/bin/env bash
# Select a cheatsheet with the tracked bspwm Rofi theme.

set -o errexit -o nounset -o pipefail

BSPWM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bspwm"
CHT_VIEWER="$BSPWM_CONFIG_DIR/bin/open-cheatsheet.sh"
CHT_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/cht.conf"
ROFI_THEME="$BSPWM_CONFIG_DIR/rofi/themes/cheatsheets.rasi"

notify_error() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "Cheatsheets" "$1"
    fi
}

load_configuration() {
    sheets_dir=""
    if [[ -r $CHT_CONFIG ]]; then
        # shellcheck source=/dev/null
        source "$CHT_CONFIG"
    fi
    sheets_dir=${sheets_dir:-"$HOME/Documents/Cheatsheets"}
}

list_cheatsheets() {
    find "$sheets_dir" -type f \
        \( -iname '*.txt' -o -iname '*.png' -o -iname '*.jpg' \
        -o -iname '*.pdf' -o -iname '*.html' -o -iname '*.md' \) \
        -not -path '*/_files/*' -printf '%P\n' | LC_ALL=C sort
}

main() {
    load_configuration

    if [[ ! -d $sheets_dir ]]; then
        notify_error "Verzeichnis nicht gefunden: $sheets_dir"
        return 1
    fi
    if [[ ! -x $CHT_VIEWER ]]; then
        notify_error "Cheatsheet-Viewer nicht gefunden: $CHT_VIEWER"
        return 1
    fi
    if [[ ! -r $ROFI_THEME ]]; then
        notify_error "Rofi-Theme nicht gefunden: $ROFI_THEME"
        return 1
    fi

    local selection
    selection="$(
        list_cheatsheets | rofi \
            -no-config \
            -dmenu \
            -i \
            -p "Cheatsheets" \
            -theme "$ROFI_THEME"
    )" || return 0

    [[ -n $selection ]] || return 0
    exec "$CHT_VIEWER" "$selection"
}

main "$@"
