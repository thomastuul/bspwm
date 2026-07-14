#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

if [[ ${DEBUG-} =~ ^(1|yes|true)$ ]]; then
    set -o xtrace
fi

cache_root="${XDG_CACHE_HOME:-$HOME/.cache}"
network_cache_dir="${NETWORK_CACHE_DIR:-$cache_root/lemonbar}"
display_cache="$network_cache_dir/network.cache"

# Normal panel updates only read the worker-owned cache.
if [[ ${1:-} != --refresh ]]; then
    if [[ -r $display_cache ]]; then
        printf '%s' "$(<"$display_cache")"
    fi
    exit 0
fi

[[ $# -eq 1 ]] || {
    printf 'Usage: %s [--refresh]\n' "$0" >&2
    exit 2
}

# shellcheck disable=SC1091
source "$LEMONDIR/config.sh"
# shellcheck source=../lib/lemonbar_action.sh
source "$LEMONDIR/lib/lemonbar_action.sh"
# shellcheck disable=SC1090
if [[ -n ${BASH_ENV:-} && -r $BASH_ENV ]]; then
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
    [[ $state == up ]]
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
    local interface=$1 name status quality

    [[ -r /proc/net/wireless ]] || return 1

    while read -r name status quality _; do
        name=${name%:}
        [[ $name == "$interface" ]] || continue

        quality=${quality%%.*}
        [[ $quality =~ ^[0-9]+$ ]] || return 1
        strength=$((quality * 100 / 70))
        ((strength > 100)) && strength=100
        return 0
    done </proc/net/wireless

    return 1
}

# Inspect every interface once and collect both WLAN and Ethernet state.
for interface_path in /sys/class/net/*; do
    [[ -e $interface_path ]] || continue
    interface=${interface_path##*/}
    [[ $interface == lo ]] && continue

    if [[ -d $interface_path/wireless || -e $interface_path/phy80211 ]]; then
        if [[ -z $wlan_string ]] && read_operstate "$interface"; then
            read_wifi_from_nmcli "$interface" ||
                read_wifi_from_proc "$interface" ||
                strength=""

            if [[ -n $strength ]]; then
                wlan_string="說 ${strength}%"
            else
                wlan_string="說"
            fi
        fi
    elif [[ -z $eth_string && -e $interface_path/device ]] &&
        read_operstate "$interface"; then
        eth_string=""
    fi
done

network_action=$(lemonbar_action \
    bash "$LEMONDIR/lib/click_action.sh" terminal nmtui)
notify_action=$(lemonbar_action \
    bash "$LEMONDIR/lib/click_action.sh" notify "Network" "SSID: $ssid")

printf '%s' \
    "%{A1:${network_action}:}%{A3:${notify_action}:}%{B$COLOR_DEFAULT_BG}%{F$COLOR_NETWORK_FG}%{+u} ${eth_string} ${wlan_string} %{-u}%{F-}%{B-}%{A}%{A}"
