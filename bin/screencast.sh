#!/usr/bin/env bash
#
# Bash-Skript
#
# License: GPL
# Author: Thomas Tuul
# 01.01.2022
# Version 0.1

LEMONDIR="${LEMONDIR:-${XDG_CONFIG_HOME:-$HOME/.config}/bspwm/lemonbar}"
# shellcheck source=../lemonbar/config.sh
source "$LEMONDIR/config.sh"

# You can also run kill -39 $(pidof dwmblocks) which will have the same effect, but is faster. Just add 34 to your typical
# signal number.

getPid() {
    local pid=""

    if [[ -r "$LEMONBAR_RUNTIME_DIR/sighandler.pid" ]]; then
        IFS= read -r pid <"$LEMONBAR_RUNTIME_DIR/sighandler.pid" || pid=""
    fi

    [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null || return 1
    printf '%s\n' "$pid"
}

TIME=$(date "+%d-%m-%Y-%H-%M-%S")

MIC_NAME_1="FIFINE K670 Microphone"
MIC_NAME_2="Poly Studio P5"

MIC=$(arecord -l | grep "$MIC_NAME_1" | cut -d ':' -f 1 | cut -d ' ' -f 2)
if [ -z $MIC ]; then
    MIC=$(arecord -l | grep "$MIC_NAME_2" | cut -d ':' -f 1 | cut -d ' ' -f 2)
elif [ -z $MIC ]; then
    printf "Kein Mikrofon vorhanden für Aufnahme!\n"
    notify-send "Kein Mikrofon vorhanden für Aufnahme!"
    exit 1
fi


# Get the window position and its size
SIZE=$(xdpyinfo | grep 'dimensions:'|awk '{print $2}')
# record screen to video file
FILE="$HOME/Videos/screencast-$TIME.mkv"

if [ -f "$XDG_RUNTIME_DIR/screencast.pid" ]; then
    pid="$(cat "$XDG_RUNTIME_DIR/screencast.pid")"
    rm -f "$XDG_RUNTIME_DIR/screencast.pid"
    kill "$pid"
    notify-send "Screencast unter ~/Videos abgelegt"
else
    ffmpeg -r 30 -f x11grab -s $(xdpyinfo | grep 'dimensions:'|awk '{print $2}') -i :0.0 \
        -itsoffset 00:00.3 -f alsa -ac 2 -i  hw:$MIC \
        -vcodec libx264 -pix_fmt yuv420p -preset ultrafast -crf 0 -threads 0 \
        -acodec pcm_s16le -y \
        "$FILE" &
        echo $! > "$XDG_RUNTIME_DIR/screencast.pid"
fi

if sighandler_pid=$(getPid); then
    kill -s "$SIGNAL_SCREENCAST" "$sighandler_pid" 2>/dev/null || true
fi
