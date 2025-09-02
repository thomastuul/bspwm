#!/usr/bin/env bash
# ~/.local/bin/app-launcher.sh
# Startet je Kategorie das erste verfügbare Programm.
# Lint-clean für ShellCheck (bash).

set -o errexit -o nounset -o pipefail

notify() {
  # Optional: kurze Info, falls nichts gefunden wurde
  if command -v notify-send >/dev/null 2>&1; then
    # shellcheck disable=SC2059
    notify-send "Launcher" "$(printf "%s" "$1")"
  fi
}

launch_first() {
  # $1 = Kategorie-Name (nur für Meldungen), restliche Args = Kandidaten
  # Rückgabe: 0 falls etwas gestartet wurde, 1 sonst
  local category
  category=$1
  shift

  local app
  for app in "$@"; do
    if command -v "$app" >/dev/null 2>&1; then
      # Vom sxhkd-Prozess lösen; falls setsid nicht klappt, normal im Hintergrund starten
      if ! setsid -f "$app" >/dev/null 2>&1; then
        "$app" >/dev/null 2>&1 &
        disown || true
      fi
      return 0
    fi
  done

  notify "Kein passendes Programm für '${category}' gefunden."
  return 1
}

main() {
  local action=${1:-}

  case "$action" in
    browser)
      launch_first "Browser" \
        brave-browser brave brave-nightly \
        firefox firefox-esr \
        chromium google-chrome \
        x-www-browser
      ;;
    mail)
      launch_first "Mail" \
        thunderbird evolution geary claws-mail
      ;;
    file)
      if ! launch_first "Dateimanager" \
        thunar nautilus nemo pcmanfm dolphin; then
        # Fallback: Home-Verzeichnis öffnen (xdg-open ist häufig vorhanden)
        if command -v xdg-open >/dev/null 2>&1; then
          setsid -f xdg-open "$HOME" >/dev/null 2>&1 || true
        else
          notify "Weder Dateimanager noch xdg-open gefunden."
          return 1
        fi
      fi
      ;;
    *)
      notify "Unbekannte Kategorie: ${action:-<leer>}"
      return 2
      ;;
  esac
}

main "$@"
