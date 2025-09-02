#!/usr/bin/env bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

set -o errexit      # Exit on most errors (see the manual)
set -o nounset      # Disallow expansion of unset variables
set -o pipefail     # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
set -o errtrace     # Ensure the error trap handler is inherited

# shellcheck disable=SC1091
source "$LEMONDIR/config.sh"

ssid="-"
wlan_adapter_list="$(ls /sys/class/ieee80211/*/device/net/)"
for wlan in $wlan_adapter_list; do
    if [[ "$(cat /sys/class/net/"${wlan}"/operstate)" == "up" ]]; then
        ssid="$(nmcli connection | grep "$wlan" | awk '{print $1}')"
        strength="$(awk 'END { print int($3 * 100 / 70) }' /proc/net/wireless | sed 's/\.$//')"
        wlan_string="說 ${strength}%"
        break
    fi
done

eth_adapter_list=()
for interface in /sys/class/net/e*; do
    [[ -e $interface ]] && eth_adapter_list+=("$(basename "$interface")")
done

eth_string=""
for eth in "${eth_adapter_list[@]}"; do
    if [[ "$(cat "/sys/class/net/${eth}/operstate")" == "up" ]]; then
        eth_string=""
        break
    fi
done

printf "%s" "%{A1:/bin/sh -c 'setsid -f \"$TERMINAL\" -e nmtui >/dev/null 2>&1 &':}%{A3:notify-send \"SSID\: $ssid\":}%{B$COLOR_DEFAULT_BG}%{F$COLOR_NETWORK_FG}%{+u} ${eth_string-} ${wlan_string-} %{-u}%{F-}%{B-}%{A}%{A}"
