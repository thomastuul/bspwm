#!/usr/bin/env bash
# Desktop-specific overrides. Unset values inherit the generic defaults.
# shellcheck disable=SC2034

BSPWM_HOST_ROLE=desktop
# shellcheck source=lib/panel-profile.sh
source "$BSPWM_CONFIG_DIR/lib/panel-profile.sh"
bspwm_panel_profile
BSPWM_WALLPAPER="${HOME}/Bilder/Wallpaper/sixtinische-haende-unicode-wallpaper-3840x2160.png"

# Prefer an exact-size variant for each active monitor.
BSPWM_WALLPAPER_PREFIX="${HOME}/Bilder/Wallpaper/sixtinische-haende-varianten/01-gold"
