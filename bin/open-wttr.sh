#!/usr/bin/env bash
set -Eeuo pipefail

# Ort konfigurieren (Umlaute vermeiden oder via WTTR_LOC überschreiben)
LOC="${WTTR_LOC:-Muenchen}"
URL="https://wttr.in/${LOC}"

# Terminal ermitteln (TERMINAL bevorzugt, sonst Fallbacks)
term="${TERMINAL:-}"
if [[ -z "${term}" ]]; then
  for t in alacritty kitty foot gnome-terminal konsole wezterm xterm; do
    command -v "$t" >/dev/null 2>&1 && { term="$t"; break; }
  done
fi
term="${term:-xterm}"

# Kommando: Farben behalten (-R), keine „auto-quit“-Übernahme (-+F), no-init (-+X)
case "$term" in
  gnome-terminal) exec "$term" -- bash -lc "curl -fsSL \"$URL\" | less -+F -+X -R" ;;
  konsole)        exec "$term" -e  bash -lc "curl -fsSL \"$URL\" | less -+F -+X -R" ;;
  *)              exec "$term" -e  bash -lc "curl -fsSL \"$URL\" | less -+F -+X -R" ;;
esac

