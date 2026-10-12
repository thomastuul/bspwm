#!/usr/bin/env bash
# Resolve Pegasus4 panel sizes from autorandr's EDID-based monitor profiles.
# shellcheck disable=SC2034

bspwm_panel_profile() {
    local profile=${AUTORANDR_CURRENT_PROFILE:-} detected
    if [[ -z $profile ]] && command -v autorandr >/dev/null 2>&1; then
        detected=$(autorandr --match-edid --detected 2>/dev/null) || detected=""
        # Only accept one unambiguous profile; unknown layouts use the baseline.
        if [[ $detected != *$'\n'* ]]; then
            profile=${detected%% *}
        fi
    fi
    BSPWM_PANEL_PROFILE=${profile:-unknown}
    case $BSPWM_PANEL_PROFILE in
        ioc-27m2u-4k)
            BSPWM_PANEL_HEIGHT=40
            BSPWM_PANEL_FONT_SIZE=17
            ;;
        *)
            BSPWM_PANEL_HEIGHT=30
            BSPWM_PANEL_FONT_SIZE=15
            ;;
    esac
    BSPWM_TOP_PADDING=$BSPWM_PANEL_HEIGHT
}
