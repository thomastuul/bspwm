#!/usr/bin/env bash
# Regression checks for monitor-layout generation.

set -o errexit -o nounset -o pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
launcher="$repository_root/bin/rofi-monitor-layout.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

cat >"$fixture/xrandr.txt" <<'EOF'
Screen 0: minimum 320 x 200, current 3840 x 1600, maximum 16384 x 16384
DP-1 disconnected (normal left inverted right x axis y axis)
DP-2 connected 1920x1080+0+0 (normal left inverted right x axis y axis)
HDMI-1 connected 1920x1080+1920+0 (normal left inverted right x axis y axis)
EOF

layouts=$(ROFI_MONITOR_XRANDR_OUTPUT="$fixture/xrandr.txt" "$launcher" --list)

[[ $layouts == *"Nur DP-2"* ]]
[[ $layouts == *"Nur HDMI-1"* ]]
[[ $layouts == *"Erweitert: DP-2 links, HDMI-1 rechts"* ]]
[[ $layouts == *"Erweitert: HDMI-1 links, DP-2 rechts"* ]]
[[ $layouts == *"Spiegeln: DP-2 und HDMI-1"* ]]
[[ $layouts != *DP-1* ]]

printf 'rofi-monitor-layout tests passed\n'
