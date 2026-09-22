#!/usr/bin/env bash
# Laptop-specific overrides. Unset values inherit the generic defaults.
# shellcheck disable=SC2034

BSPWM_HOST_ROLE=laptop
BSPWM_WALLPAPER="${HOME}/Bilder/Wallpaper/sixtinische-haende-unicode-wallpaper-3840x1600.png"

# autorandr mobile/dock profiles use this explicit output pair.
BSPWM_INTERNAL_OUTPUT=eDP-1
BSPWM_EXTERNAL_OUTPUT=HDMI-1
