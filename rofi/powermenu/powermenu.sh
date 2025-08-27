#!/usr/bin/env bash
# Rofi Power Menu – Nerd-Font-Glyphen, Mausfix & Ein-Klick-Bestätigung

set -Eeuo pipefail

############################
# Pfade & Theme
############################
SCRIPT_DIR="/home/thomas/.config/bspwm/rofi/themes"
THEME_FILE="${SCRIPT_DIR}/powermenu.rasi"

# Gemeinsame Rofi-Optionen (ohne Icons – wir nutzen Glyphen in den Labels)
ROFI_COMMON_OPTS=(-dmenu -i -p "Power")
if [[ -f "$THEME_FILE" ]]; then
  ROFI_COMMON_OPTS+=( -theme "$THEME_FILE" )
  ROFI_COMMON_OPTS+=( -theme-str 'window {width: 12em; location: North East; x-offset: -110; y-offset: 195;} listview {lines: 6;}' )
fi

############################
# Labels mit Nerd-Font-Glyphen
# (Beispiele:          )
############################
LBL_LOCK="  Lock"
LBL_LOGOUT="  Logout"
LBL_SUSPEND="  Suspend"
LBL_REBOOT="  Reboot"
LBL_SHUTDOWN="  Shutdown"
LBL_HIBERNATE="󰈨  Hibernate"

# Confirm-Strings (Deutsch; gern auch mit Glyphen)
LBL_YES="  Ja"
LBL_NO="  Nein"

############################
# Hilfsfunktionen
############################
list_items() {
  # Rein textbasiert (keine \0icon-Metadaten) – Glyphen sind Teil der Labels
  printf "%s\n" "$LBL_LOCK"
  printf "%s\n" "$LBL_LOGOUT"
  printf "%s\n" "$LBL_SUSPEND"
  printf "%s\n" "$LBL_REBOOT"
  printf "%s\n" "$LBL_SHUTDOWN"
  printf "%s\n" "$LBL_HIBERNATE"
}

# Klick-Release entprellen, damit das Bestätigungsfenster nicht sofort wieder verschwindet
debounce_click() { sleep 0.2; }

confirm_dialog() {
  local message="$1"   # z.B. "Neustart ausführen?"
  local opts=(
    -dmenu
    -i
    -p "Bestätigen"
    -mesg "$message"
    -selected-row 0                # Sicher: standardmäßig "Nein"
    -me-select-entry ''            # Linksklick soll nicht nur selektieren …
    -me-accept-entry MousePrimary  # … sondern mit einem Klick bestätigen
  )
  # kompakte Overrides für den kleinen Dialog (optional)
  local theme_overrides=(
    -theme-str 'window { location: center; anchor: center; width: 280px; }'
    -theme-str 'mainbox { children: [ "message", "listview" ]; }'
    -theme-str 'listview { columns: 2; lines: 1; dynamic: false; }'
    -theme-str 'element-text { horizontal-align: 0.5; }'
    -theme-str 'textbox { horizontal-align: 0.5; }'
  )
  if [[ -f "$THEME_FILE" ]]; then
    opts+=( -theme "$THEME_FILE" )
  fi

  debounce_click
  printf "%s\n%s\n" "$LBL_NO" "$LBL_YES" \
    | rofi "${opts[@]}" "${theme_overrides[@]}"
}

main_menu() {
  list_items | rofi "${ROFI_COMMON_OPTS[@]}"
}

# --- Medien sauber stoppen (robust, no-op wenn nicht vorhanden) ---
mpc_fadeout_and_stop() {
  command -v mpc >/dev/null || return 0
  # sanft ausblenden, wenn Volume bekannt; sonst direkt stoppen
  local vol
  vol="$(mpc volume 2>/dev/null | awk '{print $2+0}' || echo "")"
  if [[ -n "$vol" && "$vol" -gt 0 ]]; then
    # auf ~0.6s ausblenden
    for v in $(seq "$vol" -10 0); do mpc -q volume "$v"; sleep 0.06; done
  fi
  mpc -q stop
}

playerctl_pause_all() {
  command -v playerctl >/dev/null || return 0
  # alle MPRIS-Player pausieren (mpv, firefox, vlc, spotify, etc.)
  playerctl --all-players pause 2>/dev/null || true
}

pre_hook() {
  case "$1" in
    "$LBL_LOGOUT")   mpc_fadeout_and_stop; playerctl_pause_all ;;
    "$LBL_SUSPEND")  mpc_fadeout_and_stop; playerctl_pause_all ;;
    "$LBL_REBOOT")   mpc_fadeout_and_stop; playerctl_pause_all ;;
    "$LBL_SHUTDOWN") mpc_fadeout_and_stop; playerctl_pause_all ;;
    *) : ;;
  esac
}

action_for_choice() {
  local choice="$1"
  case "$choice" in
    "$LBL_LOCK")     loginctl lock-session ;;
    "$LBL_LOGOUT")
        if command -v gnome-session-quit >/dev/null; then
          gnome-session-quit --logout --no-prompt
        elif command -v bspc >/dev/null; then
          bspc quit
        else
          loginctl terminate-user "$(id -u)"
        fi
        ;;
    "$LBL_SUSPEND")   systemctl suspend-then-hibernate ;;
    "$LBL_REBOOT")    systemctl reboot ;;
    "$LBL_SHUTDOWN")  systemctl poweroff ;;
    "$LBL_HIBERNATE") systemctl hibernate ;;
    *)               return 1 ;;
  esac
}

human_action_name() {
  case "$1" in
    "$LBL_LOCK")      echo "Bildschirm sperren" ;;
    "$LBL_LOGOUT")    echo "Abmelden" ;;
    "$LBL_SUSPEND")   echo "Suspend ausführen" ;;
    "$LBL_REBOOT")    echo "Neustart ausführen" ;;
    "$LBL_SHUTDOWN")  echo "Herunterfahren ausführen" ;;
    "$LBL_HIBERNATE") echo "Hibernate ausführen" ;;
    *)               echo "$1" ;;
  esac
}

run() {
  local choice
  choice="$(main_menu || true)"
  [[ -z "${choice:-}" ]] && exit 0

  local nice_name; nice_name="$(human_action_name "$choice")"
  local answer
  answer="$(confirm_dialog "$nice_name?")" || exit 1

  if [[ "$answer" == "$LBL_YES" ]]; then
    pre_hook "$choice"
    action_for_choice "$choice"
  fi
}

run
