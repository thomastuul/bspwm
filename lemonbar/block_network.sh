#!/usr/bin/env bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

#set -o errexit      # Exit on most errors (see the manual)
#set -o nounset      # Disallow expansion of unset variables
#set -o pipefail     # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
#set -o errtrace     # Ensure the error trap handler is inherited

source "$LEMONDIR/config.sh"

wlan_adapter_list="$(ls /sys/class/ieee80211/*/device/net/)"
for wlan in $wlan_adapter_list; do
    if [[ "$(cat /sys/class/net/"${wlan}"/operstate)" == "up" ]]; then
        ssid="$(nmcli connection | grep "$wlan" | awk '{print $1}')"
        strength="$(cat /proc/net/wireless | awk 'END { print int($3 * 100 / 70) }' | sed 's/\.$//')"
        wlan_string="說 ${strength}%"
        break
    fi
done

eth_adapter_list="$(ls /sys/class/net/ | grep ^e)"
for eth in $eth_adapter_list; do
    if [[ "$(cat /sys/class/net/"${eth}"/operstate)" == "up" ]]; then
        eth_string="🌐"
        break
    fi
done

printf "%s\n" "%{B$COLOR_DEFAULT_BG}%{F$COLOR_NETWORK_FG}%{+u} ${eth_string} ${wlan_string}% %{-u}%{F-}%{B-}"
