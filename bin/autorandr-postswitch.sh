#!/usr/bin/env bash
# Reconcile bspwm desktops after autorandr changes the active RandR outputs.

set -o errexit
set -o nounset
set -o pipefail

BSPWM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bspwm"
# shellcheck source=lib/host-profile.sh
source "$BSPWM_CONFIG_DIR/lib/host-profile.sh"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/bspwm"
PROFILE="${AUTORANDR_CURRENT_PROFILE:-${1:-}}"
WALLPAPER="${WALLPAPER:-$BSPWM_WALLPAPER}"

mkdir -p -- "$STATE_DIR"

log() {
    printf '%(%F %T)T\tautorandr\t%s\n' -1 "$*" >>"$STATE_DIR/autorandr.log"
}

monitor_exists() {
    bspc query -M --names | grep -Fqx -- "$1"
}

desktop_name() {
    bspc query -D -d "$1" --names
}

desktop_named() {
    local monitor=$1 wanted=$2 desktop

    while IFS= read -r desktop; do
        if [[ $(desktop_name "$desktop") == "$wanted" ]]; then
            printf '%s\n' "$desktop"
            return 0
        fi
    done < <(bspc query -D -m "$monitor")
    return 1
}

ensure_desktop() {
    local monitor=$1 name=$2 desktop

    if desktop=$(desktop_named "$monitor" "$name"); then
        printf '%s\n' "$desktop"
        return 0
    fi
    bspc monitor "$monitor" --add-desktops "$name"
    desktop_named "$monitor" "$name"
}

move_desktop_windows() {
    local source=$1 destination=$2 node
    local -a nodes=()

    mapfile -t nodes < <(bspc query -N -d "$source" -n .window)
    for node in "${nodes[@]}"; do
        bspc node "$node" --to-desktop "$destination"
    done
}

normalize_monitor() {
    local monitor=$1 desktop name destination workspace
    local -a desktops=()
    declare -A first_by_name=()

    monitor_exists "$monitor" || return 0
    ensure_desktop "$monitor" 1 >/dev/null
    mapfile -t desktops < <(bspc query -D -m "$monitor")

    for desktop in "${desktops[@]}"; do
        name=$(desktop_name "$desktop")
        if [[ $name == Desktop ]]; then
            destination=$(ensure_desktop "$monitor" 1)
            move_desktop_windows "$desktop" "$destination"
            bspc desktop "$desktop" --remove
        elif [[ -n ${first_by_name[$name]:-} ]]; then
            destination=${first_by_name[$name]}
            move_desktop_windows "$desktop" "$destination"
            bspc desktop "$desktop" --remove
        else
            first_by_name[$name]=$desktop
        fi
    done

    for workspace in {1..9}; do
        ensure_desktop "$monitor" "$workspace" >/dev/null
    done
    bspc monitor "$monitor" --reorder-desktops 1 2 3 4 5 6 7 8 9
}

consolidate_monitor() {
    local source=$1 destination=$2 desktop name target
    local -a desktops=()

    monitor_exists "$source" || return 0
    monitor_exists "$destination" || {
        log "destination monitor is unavailable: $destination"
        return 1
    }

    normalize_monitor "$destination"
    mapfile -t desktops < <(bspc query -D -m "$source")
    for desktop in "${desktops[@]}"; do
        name=$(desktop_name "$desktop")
        [[ $name == Desktop ]] && name=1
        target=$(ensure_desktop "$destination" "$name")
        move_desktop_windows "$desktop" "$target"
    done

    bspc monitor "$source" --remove
    normalize_monitor "$destination"
    bspc monitor "$destination" --focus
}

sync_monitor_geometry() {
    local output geometry

    while read -r output geometry; do
        monitor_exists "$output" || continue
        bspc monitor "$output" --rectangle "$geometry"
    done < <(
        xrandr --query | awk '
            $2 == "connected" {
                for (field = 3; field <= NF; field++)
                    if ($field ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) {
                        print $1, $field
                        break
                    }
            }
        '
    )
}

refresh_wallpaper() {
    [[ -r $WALLPAPER ]] || return 0
    command -v xwallpaper >/dev/null 2>&1 || return 0
    xwallpaper --zoom "$WALLPAPER"
}

case $PROFILE in
    dock-closed)
        consolidate_monitor eDP-1 HDMI-1
        ;;
    mobile)
        consolidate_monitor HDMI-1 eDP-1
        ;;
    dock-open)
        normalize_monitor eDP-1
        normalize_monitor HDMI-1
        ;;
esac

sync_monitor_geometry
refresh_wallpaper

# The panel normally follows RandR and bspwm events. Restart it through the
# existing idempotent session launcher only if it exited during the switch.
if [[ -x $HOME/.local/bin/sliverbar ]] &&
    ! pgrep -u "$UID" -x sliverbar >/dev/null; then
    "$BSPWM_CONFIG_DIR/autostart" ||
        log "session launcher failed while restarting Sliverbar"
fi

log "reconciled profile=${PROFILE:-unknown} monitors=$(bspc query -M --names | paste -sd, -)"
