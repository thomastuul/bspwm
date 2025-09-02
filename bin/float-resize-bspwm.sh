#!/usr/bin/env bash
# ~/.config/bspwm/bin/float-resize-bspwm.sh
# Floating-Fenster prozentual resizen & zentrieren (robust, kompakt)
# Abhängigkeiten: bspc, jq, xdotool

set -o errexit -o nounset -o pipefail

# ---- Konfiguration -------------------------------------------------
DEFAULT_SIZE="80x80"   # Fallback (BxH in %)
declare -A SIZE_FOR=(
  ["keepassxc"]="60x80"
  ["zathura"]="30x90"
)
EXCLUDE=( "mpv" )             # z.B.: ("gimp" "krita")
# -------------------------------------------------------------------

tolower()  { printf '%s' "${1,,}"; }
in_array() { local n="$1"; shift; for e in "$@"; do [[ "$e" == "$n" ]] && return 0; done; return 1; }
size_for_class() { local c="$1"; printf '%s\n' "${SIZE_FOR[$c]:-$DEFAULT_SIZE}"; }

get_monitor_id_for_node() {
  local wid="$1" mon desk
  if mon="$(bspc query -M -n "$wid" 2>/dev/null | head -n1)"; then
    [[ -n "$mon" ]] && { printf '%s\n' "$mon"; return 0; }
  fi
  if desk="$(bspc query -D -n "$wid" 2>/dev/null | head -n1)"; then
    if mon="$(bspc query -M -d "$desk" 2>/dev/null | head -n1)"; then
      [[ -n "$mon" ]] && { printf '%s\n' "$mon"; return 0; }
    fi
  fi
  return 1
}

apply_resize_center() {
  local wid="$1"

  # Node lesen; nur echte Clients + floating bearbeiten
  local j; j="$(bspc query -T -n "$wid")" || return 0
  [[ "$(jq -r '.client? != null' <<<"$j")" == "true" ]] || return 0
  [[ "$(jq -r '.client.state'    <<<"$j")" == "floating" ]] || return 0

  # Klasse + Excludes
  local cls cls_lc
  cls="$(jq -r '.client.className // .client.class // ""' <<<"$j")"
  cls_lc="$(tolower "$cls")"
  in_array "$cls_lc" "${EXCLUDE[@]}" && return 0

  # Monitor-Rechteck
  local mon mj mx my mw mh
  if ! mon="$(get_monitor_id_for_node "$wid")"; then
    return 0
  fi
  mj="$(bspc query -T -m "$mon")" || return 0
  mx="$(jq -r '.rectangle.x'      <<<"$mj")"
  my="$(jq -r '.rectangle.y'      <<<"$mj")"
  mw="$(jq -r '.rectangle.width'  <<<"$mj")"
  mh="$(jq -r '.rectangle.height' <<<"$mj")"

  # Zielgröße/-position
  local pct pw ph tw th tx ty
  pct="$(size_for_class "$cls_lc")"
  pw="${pct%x*}"; ph="${pct#*x}"
  tw=$(( mw * pw / 100 ))
  th=$(( mh * ph / 100 ))
  tx=$(( mx + (mw - tw) / 2 ))
  ty=$(( my + (mh - th) / 2 ))

  # anwenden (+ kleiner Nachpass)
  xdotool windowsize "$wid" "$tw" "$th"
  xdotool windowmove  "$wid" "$tx" "$ty"
  ( sleep 0.12; xdotool windowsize "$wid" "$tw" "$th"; xdotool windowmove "$wid" "$tx" "$ty" ) &
}

# Events abonnieren; WID = letztes Feld jeder Zeile (robust)
bspc subscribe node_add node_state | while IFS= read -r line; do
  # letztes Token extrahieren
  read -r -a _fields <<<"$line"
  wid="${_fields[${#_fields[@]}-1]}"
  # kleine Stabilisierung
  sleep 0.08
  bspc query -T -n "$wid" >/dev/null 2>&1 && apply_resize_center "$wid"
done
