#!/usr/bin/env bash
# Select a host wallpaper variant for each active RandR output.
set -euo pipefail
BSPWM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bspwm"
unset BSPWM_HOST_PROFILE_LOADED
# shellcheck source=lib/host-profile.sh
source "$BSPWM_CONFIG_DIR/lib/host-profile.sh"
wallpaper=${WALLPAPER:-$BSPWM_WALLPAPER}
[[ -r $wallpaper ]] || exit 0
args=(--daemon --maximize "$wallpaper")
while read -r output resolution; do
    candidate="${BSPWM_WALLPAPER_PREFIX:-}-$resolution.png"
    if [[ -z ${WALLPAPER:-} && -n ${BSPWM_WALLPAPER_PREFIX:-} && -r $candidate ]]; then
        args+=(--output "$output" --maximize "$candidate")
    fi
done < <(xrandr --current | awk '
    $2 == "connected" {
        for (i = 3; i <= NF; i++)
            if ($i ~ /^[0-9]+x[0-9]+[+-][0-9]+[+-][0-9]+$/) {
                split($i, size, /[+-]/); print $1, size[1]; break
            }
    }')
if [[ ${1:-} == --print ]]; then
    printf '%s\n' "${args[@]}"
    exit 0
fi
runtime=${XDG_RUNTIME_DIR:-/run/user/$UID}/bspwm
mkdir -p -- "$runtime"
exec 8>"$runtime/wallpaper.lock"
flock 8
expected=$(printf '%s\n' "${args[@]}")
pids=()
while read -r pid; do
    [[ -r /proc/$pid/cmdline && -r /proc/$pid/environ ]] || continue
    argv=()
    mapfile -d '' -t argv <"/proc/$pid/cmdline" || continue
    # Only replace this display's managed motif, preserving other sessions.
    same_display=0
    while IFS= read -r -d '' entry; do
        [[ $entry == "DISPLAY=${DISPLAY:-}" ]] && same_display=1
    done <"/proc/$pid/environ"
    ((same_display)) || continue
    managed=0
    for argument in "${argv[@]:1}"; do
        [[ $argument == "$wallpaper" ]] && managed=1
        if [[ -n ${BSPWM_WALLPAPER_PREFIX:-} && $argument == "$BSPWM_WALLPAPER_PREFIX"-*.png ]]; then
            managed=1
        fi
    done
    ((managed)) || continue
    [[ $(printf '%s\n' "${argv[@]:1}") == "$expected" ]] && exit 0
    pids+=("$pid")
done < <(pgrep -u "$UID" -x xwallpaper || true)
for pid in "${pids[@]}"; do
    kill -TERM "$pid"
done
xwallpaper "${args[@]}" 8>&-
