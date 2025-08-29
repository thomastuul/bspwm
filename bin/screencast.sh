#!/usr/bin/env bash
#
# Bash-Skript
#
# License: GPL
# Author: Thomas Tuul
# 01.01.2022
# Version 0.1

# You can also run kill -39 $(pidof dwmblocks) which will have the same effect, but is faster. Just add 34 to your typical
# signal number.

getPid() {
    PID=$(pgrep -f sighandler.sh)

    echo $PID
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
FILE="/home/thomas/Videos/screencast-$TIME.mkv"

if [ -f /tmp/screencastpid ]; then
    pid="$(cat /tmp/screencastpid)"
    rm -f /tmp/screencastpid
    killall ffmpeg
    notify-send "Screencast unter ~/Videos abgelegt"
else
    ffmpeg -r 30 -f x11grab -s $(xdpyinfo | grep 'dimensions:'|awk '{print $2}') -i :0.0 \
        -itsoffset 00:00.3 -f alsa -ac 2 -i  hw:$MIC \
        -vcodec libx264 -pix_fmt yuv420p -preset ultrafast -crf 0 -threads 0 \
        -acodec pcm_s16le -y \
        "$FILE" &
        echo $! > /tmp/screencastpid
fi

kill -RTMIN+11 "$(getPid)"
