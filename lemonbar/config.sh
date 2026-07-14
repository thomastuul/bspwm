# shellcheck disable=2034

TERMINAL=${TERMINAL:-alacritty}
LEMONBAR_RUNTIME_DIR=${LEMONBAR_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/run/user/${UID:-$(id -u)}}/lemonbar}

# Derive realtime signals from the platform instead of assuming SIGRTMIN=34.
SIGNAL_RTMIN=${SIGNAL_RTMIN:-$(kill -l RTMIN 2>/dev/null || printf '34')}
case $SIGNAL_RTMIN in
'' | *[!0-9]*) SIGNAL_RTMIN=34 ;;
esac
SIGNAL_WORKSPACE=$((SIGNAL_RTMIN + 2))
SIGNAL_TICK=$((SIGNAL_RTMIN + 3))
SIGNAL_TITLE=$((SIGNAL_RTMIN + 5))
SIGNAL_VOLUME=$((SIGNAL_RTMIN + 6))
SIGNAL_BRIGHTNESS_UP=$((SIGNAL_RTMIN + 7))
SIGNAL_BRIGHTNESS_DOWN=$((SIGNAL_RTMIN + 8))
SIGNAL_TRAY=$((SIGNAL_RTMIN + 9))
SIGNAL_NETWORK=$((SIGNAL_RTMIN + 10))
SIGNAL_SCREENCAST=$((SIGNAL_RTMIN + 11))

# Collect state-change bursts before updating and rendering the panel.
SIGNAL_DEBOUNCE_DELAY=${SIGNAL_DEBOUNCE_DELAY:-0.03}
WORKER_RESTART_DELAY=${WORKER_RESTART_DELAY:-2}
CACHE_STALE_MAX_AGE=${CACHE_STALE_MAX_AGE:-300}

# Dracula color palette
BGlighter="#424450"
BGlight="#343746"
Background="#282A36"
BGdark="#21222C"
BGdarker="#191A21"
Selection="#bfbfbf"
Foreground="#f8f8f2"
Comment="#6272a4"
Cyan="#8be9fd"
Green="#50fa7b"
Orange="#ffb86c"
Pink="#ff79c6"
Purple="#bd93f9"
Red="#ff5555"
Yellow="#f1fa8c"
Color_0="#21222C"
Color_1="#FF5555"
Color_2="#50FA7B"
Color_3="#F1FA8C"
Color_4="#BD93F9"
Color_5="#FF79C6"
Color_6="#8BE9FD"
Color_7="#F8F8F2"
Color_8="#6272A4"
Color_9="#FF6E6E"
Color_10="#69FF94"
Color_11="#FFFFA5"
Color_12="#D6ACFF"
Color_13="#FF92DF"
Color_14="#A4FFFF"
Color_15="#FFFFFF"

COLOR_DEFAULT_FG="$Red"
COLOR_DEFAULT_BG="$Background"
COLOR_MONITOR_BG="$Background"
COLOR_FREE_FG="$Selection"
COLOR_FREE_BG="$BGdarker"
COLOR_PANEL_BG="$BGdarker"
COLOR_FOCUSED_FREE_FG="$Green"
COLOR_FOCUSED_FREE_BG="$BGdark"
COLOR_OCCUPIED_FG="$Red"
COLOR_OCCUPIED_BG="$BGdarker"
COLOR_FOCUSED_OCCUPIED_FG="$Color_10"
COLOR_FOCUSED_OCCUPIED_BG="$BGdarker"
COLOR_URGENT_FG="$Color_9"
COLOR_URGENT_BG="$BGlight"
COLOR_FOCUSED_URGENT_FG="$BGlight"
COLOR_FOCUSED_URGENT_BG="$Color_9"
COLOR_SYS_FG="$Yellow"
COLOR_FOREGROUND="$Color_6"
COLOR_CLOCK_FG="$Green"
COLOR_VOLUME_FG="$Pink"
COLOR_VOLUME_FG_MUTED="$Red"
COLOR_MONITOR_FG="$Purple"
COLOR_NETWORK_FG="$Cyan"
COLOR_SCREENCAST_FG="$Red"
COLOR_WEATHER_FG="$Purple"
COLOR_BATTERY_FG="$Orange"
COLOR_BATTERY_WARN_FG="$Yellow"
COLOR_BATTERY_CRIT_FG="$Red"
COLOR_BATTERY_CHARGING_FG="$Green"

PADDING=" "
CLICKABLE_AREAS=30
PANEL_HORIZONTAL_OFFSET=0
PANEL_VERTICAL_OFFSET=0
PANEL_FONT="JetBrainsMono:style=Regular:size=9"
PANEL_ICON_FONT="Hack Nerd Font Mono:style=Regular:size=11"
UNDERLINE_HEIGHT=0
PANEL_WM_NAME="lemonbar"
SYSTRAY_WM_NAME="panel" # The X11 window name, not the executable name.
TITLE_MAX_LENGTH=${TITLE_MAX_LENGTH:-45}
# Compatibility alias for older local modules.
TITLE_MAX_LENGHT=$TITLE_MAX_LENGTH
