#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

# Enable xtrace for explicit debug runs.
if [[ ${DEBUG-} =~ ^(1|yes|true)$ ]]; then
    set -o xtrace
fi

# shellcheck disable=SC1091
source "$LEMONDIR/config.sh"
# shellcheck source=../lib/lemonbar_action.sh
source "$LEMONDIR/lib/lemonbar_action.sh"
# shellcheck disable=SC1090
if [[ -n "${BASH_ENV:-}" && -r "$BASH_ENV" ]]; then
    # shellcheck source=../lib/logging_env.sh
    source "$BASH_ENV"
else
    printf 'BASH_ENV not found: %s\n' "${BASH_ENV:-unset}" >&2
    exit 1
fi

ssid="-"
strength=""
wlan_string=""
eth_string=""

read_operstate() {
    local interface=$1 state_file="/sys/class/net/$1/operstate"
    local state=""

    [[ -r $state_file ]] || return 1
    IFS= read -r state <"$state_file"
    [[ $state == "up" ]]
}

read_wifi_from_nmcli() {
    local interface=$1 line payload

    command -v nmcli >/dev/null 2>&1 || return 1

    while IFS= read -r line; do
        [[ $line == '*:'* ]] || continue

        payload=${line#*:}
        strength=${payload##*:}
        ssid=${payload%:*}

        [[ $strength =~ ^[0-9]+$ ]] || strength=""
        [[ -n $ssid ]] || ssid="-"
        return 0
    done < <(
        nmcli --terse --escape no --fields IN-USE,SSID,SIGNAL \
            device wifi list --rescan no ifname "$interface" 2>/dev/null
    )

    return 1
}

read_wifi_from_proc() {
    local interface=$1

    [[ -r /proc/net/wireless ]] || return 1
    strength=$(
        awk -v interface="$interface" '
            $1 == interface ":" {
                value = int($3 * 100 / 70)
                if (value < 0) value = 0
                if (value > 100) value = 100
                print value
            }
        ' /proc/net/wireless
    )

    [[ $strength =~ ^[0-9]+$ ]]
}

for interface_path in /sys/class/net/*; do
    [[ -e $interface_path ]] || continue
    interface=${interface_path##*/}

    if [[ -d $interface_path/wireless || -e $interface_path/phy80211 ]]; then
        if read_operstate "$interface"; then
            read_wifi_from_nmcli "$interface" ||
                read_wifi_from_proc "$interface" ||
                strength=""

            if [[ -n $strength ]]; then
                wlan_string="說 ${strength}%"
            else
                wlan_string="說"
            fi
            break
        fi
    fi
done

for interface_path in /sys/class/net/*; do
    [[ -e $interface_path ]] || continue
    interface=${interface_path##*/}

    [[ $interface == "lo" ]] && continue
    [[ -d $interface_path/wireless || -e $interface_path/phy80211 ]] &&
        continue
    [[ -e $interface_path/device ]] || continue

    if read_operstate "$interface"; then
        eth_string=""
        break
    fi
done

network_action=$(lemonbar_action \
    bash "$LEMONDIR/lib/click_action.sh" terminal nmtui)
notify_action=$(lemonbar_action \
    bash "$LEMONDIR/lib/click_action.sh" notify "Network" "SSID: $ssid")

printf '%s' \
    "%{A1:${network_action}:}%{A3:${notify_action}:}%{B$COLOR_DEFAULT_BG}%{F$COLOR_NETWORK_FG}%{+u} ${eth_string} ${wlan_string} %{-u}%{F-}%{B-}%{A}%{A}"
