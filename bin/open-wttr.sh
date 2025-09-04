#!/bin/sh
# open-wttr.sh — Cache-only Anzeige in einem Terminal (für Lemonbar-Event)
# -----------------------------------------------------------------------
# Liest NUR den von sb-forecast.sh erzeugten Cache und zeigt ihn in einem
# Terminal mit 'less' an. Kein Netzwerkzugriff.
#
# Umgebung (konsistent zu sb-forecast.sh):
#   DEFAULT_LOCATION  – Standard-Ort (Default: München)
#   WEATHERREPORT     – Cache-Prefix/Pfad (Default: ${XDG_CACHE_HOME:-$HOME/.cache}/weather)
#
# Aufruf (z. B. per Lemonbar Rechtsklick):
#   open-wttr.sh [Ort]
#
# Erwartete Cache-Datei (von sb-forecast.sh zuvor angelegt):
#   ${WEATHERREPORT}_${slug}
#   wobei slug = Ort mit ' ' und '/' ersetzt durch '_'
#
set -eu

DEFAULT_LOCATION="${DEFAULT_LOCATION:-München}"
WEATHERREPORT="${WEATHERREPORT:-${XDG_CACHE_HOME:-$HOME/.cache}/weather}"

LOCATION="${1:-$DEFAULT_LOCATION}"
slug=$(printf '%s' "$LOCATION" | tr ' /' '_')
cache_file="${WEATHERREPORT}_${slug}"

open_in_terminal() {
    # Öffnet ein Terminal und führt den übergebenen Befehl aus.
    # Nutzt $TERMINAL wenn gesetzt, sonst gängige Fallbacks.
    cmd="$1"

    if [ -n "${TERMINAL:-}" ]; then
        # Häufige $TERMINALs korrekt behandeln
        case "$TERMINAL" in
            *alacritty*) exec "$TERMINAL" -e sh -lc "$cmd" ;;
            *kitty*)     exec "$TERMINAL" -e sh -lc "$cmd" ;;
            *gnome-terminal*|*kgx*)
                         exec "$TERMINAL" -- bash -lc "$cmd" ;;
            *konsole*)   exec "$TERMINAL" -e bash -lc "$cmd" ;;
            *xfce4-terminal*)
                         exec "$TERMINAL" -e bash -lc "$cmd" ;;
            *xterm*)     exec "$TERMINAL" -e sh -lc "$cmd" ;;
            *)           exec "$TERMINAL" -e sh -lc "$cmd" ;;
        esac
    fi

    # Fallback-Kaskade
    if command -v alacritty >/dev/null 2>&1; then
        exec alacritty -e sh -lc "$cmd"
    elif command -v kitty >/dev/null 2>&1; then
        exec kitty -e sh -lc "$cmd"
    elif command -v gnome-terminal >/dev/null 2>&1; then
        exec gnome-terminal -- bash -lc "$cmd"
    elif command -v konsole >/dev/null 2>&1; then
        exec konsole -e bash -lc "$cmd"
    elif command -v xfce4-terminal >/dev/null 2>&1; then
        exec xfce4-terminal -e bash -lc "$cmd"
    elif command -v xterm >/dev/null 2>&1; then
        exec xterm -e sh -lc "$cmd"
    else
        echo "Kein Terminal-Emulator gefunden (alacritty/kitty/gnome-terminal/konsole/xfce4-terminal/xterm)." >&2
        exit 127
    fi
}

if [ -s "$cache_file" ]; then
    # -R: Roh-Steuerzeichen (Farben) anzeigen, falls vorhanden
    # -+F: Follow-Modus deaktivieren (less bleibt „normal“)
    # -+X: Bildschirm am Ende nicht leeren
    open_in_terminal "less -R -+F -+X \"${cache_file}\""
    exit 0
fi

msg="Kein Wetter-Cache gefunden für \"$LOCATION\".\nBitte zuerst den Cache erzeugen: sb-forecast.sh \"$LOCATION\""
if command -v notify-send >/dev/null 2>&1; then
    notify-send "Wetter-Cache fehlt" "$msg"
fi
# Optional zusätzlich im Terminal anzeigen, damit man die Meldung sieht
open_in_terminal "printf '%s\n' \"${msg}\"; printf '\n[Beliebige Taste schließt]\n'; read -r _"
exit 1
