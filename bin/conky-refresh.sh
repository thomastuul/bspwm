#!/usr/bin/env bash
# Publish generated geometry atomically and reload only this session's Conky.
set -euo pipefail

BSPWM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bspwm"
# shellcheck source=lib/host-profile.sh
source "$BSPWM_CONFIG_DIR/lib/host-profile.sh"
bspwm_feature_enabled BSPWM_ENABLE_CONKY || exit 0
launcher=${CONKY_START:-${XDG_CONFIG_HOME:-$HOME/.config}/conky/start-conky.sh}
[[ -x $launcher ]] || exit 0
runtime=${XDG_RUNTIME_DIR:-/run/user/$UID}
mkdir -p -- "$runtime/bspwm"
exec 8>"$runtime/bspwm/conky.lock"
flock 8

# The external generator must support CONKY_GENERATE_ONLY and XDG_RUNTIME_DIR.
# Isolate its non-atomic writes from the configuration used by the live process.
staging=$(mktemp -d "$runtime/bspwm/conky.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT
config="$runtime/conky-$UID.conf"

geometry() {
    xrandr --current | awk '
        $2 == "connected" {
            for (i = 3; i <= NF; i++) {
                if ($i ~ /^[0-9]+x[0-9]+[+-][0-9]+[+-][0-9]+$/) {
                    if ($3 == "primary") { primary = $i }
                    if (fallback == "") { fallback = $i }
                }
            }
        }
        END { print primary != "" ? primary : fallback }
    '
}

before=$(geometry)
[[ $before =~ ^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$ ]] || { printf 'conky: no supported active geometry\n' >&2; exit 1; }
# Match Xinerama by rectangle, including offsets; RandR output order is not a
# reliable Xinerama head index on multi-monitor desktops.
head=$(xdpyinfo -ext XINERAMA | awk -v wanted="$before" '
    $1 == "head" {
        split($5, offset, ",")
        rectangle = $3 "+" offset[1] "+" offset[2]
        if (rectangle == wanted) {
            gsub(/[#:]/, "", $2)
            print $2
            exit
        }
    }
')
[[ $head =~ ^[0-9]+$ ]] || { printf 'conky: target Xinerama head unavailable\n' >&2; exit 1; }
CONKY_GENERATE_ONLY=1 XDG_RUNTIME_DIR="$staging" "$launcher" >/dev/null
[[ -s $staging/conky-$UID.conf ]] || { printf 'conky: generator produced no configuration\n' >&2; exit 1; }
printf '\n-- bspwm target rectangle: %s\nconky.config.xinerama_head = %s\n' "$before" "$head" >>"$staging/conky-$UID.conf"
[[ $(geometry) == "$before" ]] || { printf 'conky: topology changed during generation; next hook will retry\n' >&2; exit 1; }

# Match the full configuration argument, never all processes named conky.
# This also adopts the existing launcher's instance at the same runtime path.
managed_pids() {
    local pid arg
    local -a argv=()
    while IFS= read -r pid; do
        [[ -r /proc/$pid/cmdline ]] || continue
        mapfile -d '' -t argv <"/proc/$pid/cmdline" || continue
        for arg in "${argv[@]}"; do
            if [[ $arg == "--config=$config" ]]; then
                printf '%s\n' "$pid"
                break
            fi
        done
    done < <(pgrep -u "$UID" -x conky || true)
}
mapfile -t pids < <(managed_pids)
if [[ -r $config ]] && cmp -s "$staging/conky-$UID.conf" "$config" && ((${#pids[@]})); then
    exit 0
fi
chmod 600 "$staging/conky-$UID.conf"
mv -f -- "$staging/conky-$UID.conf" "$config"
if ((${#pids[@]})); then
    for pid in "${pids[@]}"; do
        kill -USR1 "$pid"
    done
else
    conky --daemonize --config="$config" --pause=2 --quiet 8>&-
fi
