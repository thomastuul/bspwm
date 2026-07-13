# Runtime values that require access to the active X11 and bspwm session.

PANEL_WIDTH=$(
    xdpyinfo |
        awk '/dimensions/ { split($2, size, "x"); print size[1]; exit }'
)
PANEL_HEIGHT=$(bspc config top_padding)

if [[ ! $PANEL_WIDTH =~ ^[0-9]+$ || ! $PANEL_HEIGHT =~ ^[0-9]+$ ]]; then
    printf 'Unable to determine panel geometry: width=%s height=%s\n' \
        "$PANEL_WIDTH" "$PANEL_HEIGHT" >&2
    return 1
fi
