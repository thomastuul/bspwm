#!/usr/bin/env bash

dir="$HOME/.config/bspwm/rofi/themes"
theme='launcher'

rofi -show drun -theme ${dir}/${theme}.rasi \
    -theme-str 'window {location: North West; x-offset: 340; y-offset: 260;}'
