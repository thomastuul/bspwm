#!/usr/bin/env bash
#
# Bash-Skript
#
# License: GPL
# Author: Thomas Tuul
# 01.01.2022
# Version 0.1

# v4l2-ctl --list-devices
# v4l2-ctl --list-formats-ext --device /dev/video4

NODE=$(v4l2-ctl --list-devices | grep -w -A 1 "Poly" | grep "video" | awk '{$1=$1};1')

if [[ -z "$NODE" ]]; then
    NODE="/dev/video0"
fi

pkill -f /dev/video || mpv --geometry=-0-0 --autofit=20% $NODE --video-sync=audio --no-cache --no-demuxer-thread --vd-lavc-threads=1
