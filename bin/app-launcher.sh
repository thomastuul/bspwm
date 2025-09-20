#!/usr/bin/env bash
# ~/.local/bin/app-launcher.sh
# Launch the first available application for a given category exactly once.

set -o errexit
set -o nounset
set -o pipefail

# --- helpers -----------------------------------------------------------------

# DESC: Send desktop notification if notify-send exists
# ARGS: $1 - message text
notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "Launcher" "$1" || true
    fi
}

# DESC: Launch first available command from the candidates
# ARGS: $1 - category label (for messages), $2..$n - command candidates
# RET : 0 on success, 1 if none found/launched
launch_first() {
    local category
    category="$1"
    shift

    local app
    for app in "$@"; do
        if command -v "$app" >/dev/null 2>&1; then
            # Detach cleanly from parent (e.g., sxhkd) and ignore output
            if setsid -f -- "$app" >/dev/null 2>&1; then
                notify "Started ${category}: ${app}"
                return 0
            fi
            # Fallback start if setsid failed
            "$app" >/dev/null 2>&1 &
            notify "Started ${category}: ${app}"
            return 0
        fi
    done

    notify "No application found for ${category}"
    return 1
}

# --- main --------------------------------------------------------------------

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "" ]]; then
    cat <<'EOF'
Usage: app-launcher.sh <category>

Categories:
  web        -> firefox, brave, chromium, google-chrome, vivaldi
  term       -> alacritty, kitty, wezterm, urxvt, xterm, gnome-terminal
  editor     -> nvim, vim, micro, nano, code, codium
  file       -> thunar, nautilus, nemo, pcmanfm, dolphin  (fallback: xdg-open $HOME)
  mail       -> thunderbird, evolution, geary
  music      -> ncmpcpp, ncmpc, strawberry, clementine
  pdf        -> zathura, evince, okular, atril
  image      -> gimp, krita, pinta
  video      -> mpv, vlc, celluloid
  chat       -> telegram-desktop, signal-desktop, discord

Examples:
  app-launcher.sh web
  app-launcher.sh term
EOF
    exit 0
fi

case "$1" in
web)
    launch_first "Web browser" \
        firefox brave chromium google-chrome vivaldi
    ;;
term)
    launch_first "Terminal" \
        alacritty kitty wezterm urxvt xterm gnome-terminal
    ;;
editor)
    launch_first "Editor" \
        nvim vim micro nano code codium
    ;;
file)
    # Try dedicated file managers first; fallback to opening $HOME
    if ! launch_first "File manager" \
        thunar nautilus nemo pcmanfm dolphin; then
        if command -v xdg-open >/dev/null 2>&1; then
            setsid -f -- xdg-open "$HOME" >/dev/null 2>&1 || true
            notify "Opened HOME via xdg-open"
        else
            notify "No file manager or xdg-open available"
            exit 1
        fi
    fi
    ;;
mail)
    launch_first "Mail client" \
        thunderbird evolution geary
    ;;
music)
    launch_first "Music player" \
        ncmpcpp ncmpc strawberry clementine
    ;;
pdf)
    launch_first "PDF viewer" \
        zathura evince okular atril
    ;;
image)
    launch_first "Image editor" \
        gimp krita pinta
    ;;
video)
    launch_first "Video player" \
        mpv vlc celluloid
    ;;
chat)
    launch_first "Chat client" \
        telegram-desktop signal-desktop discord
    ;;
*)
    notify "Unknown category: ${1}"
    printf 'Unknown category: %s\n' "$1" >&2
    exit 2
    ;;
esac
