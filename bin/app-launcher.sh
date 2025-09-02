#!/usr/bin/env bash
# ~/.local/bin/app-launcher.sh
# Startet je Kategorie das erste verfügbare Programm genau einmal.

set -o errexit -o nounset -o pipefail

notify() { command -v notify-send >/dev/null 2>&1 && notify-send "Launcher" "$1" || true; }

launch_first() {
  # $1 = Kategorie-Name (für Meldungen), restliche Args = Kandidaten-Binärdateien
  local category="$1"; shift
  for app in "$@"; do
    if command -v "$app" >/dev/null 2>&1; then
      # Start sauber vom sxhkd-Prozess lösen:
      setsid -f "$app" >/dev/null 2>&1 || "$app" >/dev/null 2>&1 &
      exit 0   # WICHTIG: Nach dem ersten Start sofort beenden -> kein Doppelstart
    fi
  done
  notify "Kein passendes Programm für '$category' gefunden."
  exit 1
}

case "${1:-}" in
  browser)
    launch_first "Browser" brave-browser brave brave-nightly firefox firefox-esr chromium google-chrome x-www-browser
    ;;
  mail)
    launch_first "Mail" thunderbird evolution geary claws-mail
    ;;
  file)
    # Falls kein Dateimanager vorhanden ist, notfalls xdg-open $HOME
    if launch_first "Dateimanager" thunar nautilus nemo pcmanfm dolphin; then
      :
    else
      setsid -f xdg-open "$HOME" >/dev/null 2>&1 || true
    fi
    ;;
  *)
    notify "Unbekannte Kategorie: ${1:-<leer>}"
    exit 2
    ;;
esac
