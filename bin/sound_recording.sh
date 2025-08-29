#!/usr/bin/env bash
#
# Bash-Skript
#
# License: GPL
# Author: Thomas Tuul
# 04.02.2023
# Version 0.1

# get devive with: arecord -L
# here: FIFINE K670 Microphone

set -x

TIME=$(date "+%d-%m-%Y-%H-%M-%S")
MIC_NAME=""^hw:CARD=Microphone
FILE="/home/thomas/Videos/soundrecording-$TIME.wav"

MIC=$(arecord -L | grep "$MIC_NAME")
if [ -n $MIC ]; then
    printf "Nehme \"$FILE\" auf. Stop mit <STRG-C>.\n"
else
    printf "Kein Mikrofon vorhanden für Aufnahme!\n"
    exit 1
fi

arecord -f cd --device="$MIC" "$FILE"
