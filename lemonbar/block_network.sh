#!/usr/bin/env bash

source "$LEMONDIR/config.sh"

wlan_adapter_list="$(ls /sys/class/net/ | grep ^wl)"
for wlan in $wlan_adapter_list; do
    if [[ "$(cat /sys/class/net/${wlan}/operstate)" == "up" ]]; then
        ssid="$(nmcli connection | grep $wlan | awk '{print $1}')"
        strength="$(cat /proc/net/wireless | awk 'END { print int($3 * 100 / 70) }' | sed 's/\.$//')"
        wlan_string="說 ${strength}%"
        break
    fi
done

eth_adapter_list="$(ls /sys/class/net/ | grep ^e)"
for eth in $eth_adapter_list; do
    if [[ "$(cat /sys/class/net/${eth}/operstate)" == "up" ]]; then
        eth_string="🌐"
        break
    fi
done

printf "%s\n" "%{B$COLOR_DEFAULT_BG}%{F$COLOR_NETWORK_FG}%{+u} ${eth_string} ${wlan_string}% %{-u}%{F-}%{B-}"
