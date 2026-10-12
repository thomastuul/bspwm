#!/usr/bin/env bash
# Reconcile Pegasus4's panel configuration, process and reserved screen space.
set -euo pipefail

BSPWM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bspwm"
unset BSPWM_HOST_PROFILE_LOADED
# shellcheck source=lib/host-profile.sh
source "$BSPWM_CONFIG_DIR/lib/host-profile.sh"
[[ $BSPWM_HOST_NAME == Pegasus4 ]] || exit 0
bspwm_feature_enabled BSPWM_ENABLE_SLIVERBAR || exit 0

binary=$HOME/.local/bin/sliverbar
base=${SLIVERBAR_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/sliverbar/panel.conf}
[[ -x $binary && -r $base ]] || { printf 'sliverbar-refresh: binary or base configuration missing\n' >&2; exit 1; }
display_key=${DISPLAY:-}
display_key=${display_key//[^a-zA-Z0-9_.-]/_}
runtime=${XDG_RUNTIME_DIR:-/run/user/$UID}/bspwm/sliverbar-${display_key:-default}
mkdir -p -- "$runtime"
chmod 700 "$runtime"
exec 8>"$runtime/refresh.lock"
flock 8
config=$runtime/panel.conf
stamp=$runtime/applied
temporary=$(mktemp "$runtime/panel.XXXXXX")
trap 'rm -f -- "$temporary"' EXIT

# Preserve all module settings, font families and styles from the user's base.
awk -v height="$BSPWM_PANEL_HEIGHT" -v size="$BSPWM_PANEL_FONT_SIZE" '
    /^height=/ { $0 = "height=" height; heights++ }
    /^(font|icon_font)=/ {
        key = $0; sub(/=.*/, "", key); fonts[key]++
        if ($0 ~ /:size=[^:]*/) sub(/:size=[^:]*/, ":size=" size)
        else $0 = $0 ":size=" size
    }
    { print }
    END { if (heights != 1 || fonts["font"] != 1 || fonts["icon_font"] != 1) exit 1 }
' "$base" >"$temporary"
"$binary" --config "$temporary" --check-config >/dev/null

# Only adopt the installed binary on this display with our known config paths.
managed_pids() {
    local pid entry same_display selected index
    local -a argv=()
    while read -r pid; do
        [[ $(readlink -f "/proc/$pid/exe" 2>/dev/null) == "$(readlink -f "$binary")" ]] || continue
        [[ -r /proc/$pid/environ && -r /proc/$pid/cmdline ]] || continue
        same_display=0
        selected=""
        while IFS= read -r -d '' entry; do
            [[ $entry == "DISPLAY=${DISPLAY:-}" ]] && same_display=1
            [[ $entry == SLIVERBAR_CONFIG=* ]] && selected=${entry#*=}
        done <"/proc/$pid/environ"
        ((same_display)) || continue
        mapfile -d '' -t argv <"/proc/$pid/cmdline"
        for ((index = 1; index < ${#argv[@]} - 1; index++)); do
            [[ ${argv[index]} == --config ]] && selected=${argv[index + 1]}
        done
        [[ -z $selected || $selected == "$base" || $selected == "$config" ]] || continue
        printf '%s\n' "$pid"
    done < <(pgrep -u "$UID" -x sliverbar || true)
}

mapfile -t pids < <(managed_pids)
digest=$(sha256sum "$temporary")
digest=${digest%% *}
padding=$(bspc config top_padding) || exit 1
hidden=0
if ((${#pids[@]})) && [[ $padding == 0 ]]; then
    hidden=1
fi
if ((${#pids[@]} == 1)) && [[ -r $config && -r $stamp ]] &&
    cmp -s "$temporary" "$config" && [[ $(<"$stamp") == "${pids[0]} $digest" ]]; then
    ((hidden)) || bspc config top_padding "$BSPWM_PANEL_HEIGHT"
    exit 0
fi

# Validation happened before stopping anything. Never force-kill a stuck panel.
for pid in "${pids[@]}"; do
    kill -TERM "$pid"
done
for pid in "${pids[@]}"; do
    for ((attempt = 0; attempt < 100; attempt++)); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then
        printf 'sliverbar-refresh: panel %s did not stop\n' "$pid" >&2
        exit 1
    fi
done
mv -f -- "$temporary" "$config"
log=${XDG_STATE_HOME:-$HOME/.local/state}/bspwm/sliverbar-refresh.log
mkdir -p -- "$(dirname -- "$log")"
nohup "$binary" --config "$config" </dev/null >>"$log" 2>&1 8>&- 9>&- &
pid=$!
sleep 0.3
kill -0 "$pid" 2>/dev/null || { printf 'sliverbar-refresh: panel failed to start; see %s\n' "$log" >&2; exit 1; }
if ((hidden)); then
    xdo hide -a sliverbar
else
    bspc config top_padding "$BSPWM_PANEL_HEIGHT"
fi
printf '%s %s\n' "$pid" "$digest" >"$stamp"
printf '%(%F %T)T profile=%s height=%s font=%s pid=%s\n' -1 \
    "$BSPWM_PANEL_PROFILE" "$BSPWM_PANEL_HEIGHT" "$BSPWM_PANEL_FONT_SIZE" "$pid" >>"$log"
