#!/usr/bin/env bash
# Laptop-specific overrides. Unset values inherit the generic defaults.
# shellcheck disable=SC2034

BSPWM_HOST_ROLE=laptop
BSPWM_WALLPAPER="${HOME}/Bilder/Wallpaper/sixtinische-haende-unicode-wallpaper-3840x1600.png"

# autorandr mobile/dock profiles use this explicit output pair.
BSPWM_INTERNAL_OUTPUT=eDP-1
BSPWM_EXTERNAL_OUTPUT=HDMI-1

# Preserve the laptop's original screen lock and power timings.
BSPWM_SAVER_TIMEOUT_SEC=300
BSPWM_SAVER_CYCLE_SEC=10
BSPWM_DIM_TIME_MS=10000
BSPWM_DPMS_STANDBY_SEC=400
BSPWM_DPMS_SUSPEND_SEC=600
BSPWM_DPMS_OFF_SEC=900
BSPWM_AUTO_SLEEP_MIN=30
