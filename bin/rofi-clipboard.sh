#!/usr/bin/env bash
# Show Greenclip history with the tracked Dracula desktop theme.

set -o errexit -o nounset -o pipefail

BSPWM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bspwm"
GREENCLIP="$HOME/.local/share/greenclip/greenclip"
ROFI_THEME="$BSPWM_CONFIG_DIR/rofi/themes/clipboard.rasi"

if [[ ! -x $GREENCLIP ]]; then
    command -v notify-send >/dev/null 2>&1 && \
        notify-send "Zwischenablage" "Greenclip wurde nicht gefunden: $GREENCLIP"
    exit 1
fi

exec rofi \
    -no-config \
    -modi "clipboard:$GREENCLIP print" \
    -show clipboard \
    -display-clipboard "Zwischenablage" \
    -run-command '{cmd}' \
    -theme "$ROFI_THEME"
