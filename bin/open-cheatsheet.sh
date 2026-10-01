#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Open one exact cheatsheet path with an appropriate desktop or terminal viewer.
# Reworked from the GPLv3 "cht" viewer previously installed under ~/.local/share.

set -o errexit -o nounset -o pipefail

CHT_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/cht.conf"

notify_error() {
    printf 'open-cheatsheet: %s\n' "$1" >&2
    if [[ ${CHEATSHEET_NOTIFY:-1} == 1 ]] && command -v notify-send >/dev/null 2>&1; then
        notify-send "Cheatsheets" "$1"
    fi
}

usage() {
    printf 'Usage: %s [--dry-run] RELATIVE_PATH\n' "${0##*/}"
}

load_configuration() {
    sheets_dir=""
    terminal=${TERMINAL:-alacritty}
    md_viewer=glow
    text_viewer=less
    desktop_opener=xdg-open

    if [[ -r $CHT_CONFIG ]]; then
        # shellcheck source=/dev/null
        source "$CHT_CONFIG"
    fi
    sheets_dir=${sheets_dir:-"$HOME/Documents/Cheatsheets"}
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        notify_error "Programm nicht gefunden: $1"
        return 1
    fi
}

print_command() {
    printf '%q ' "$@"
    printf '\n'
}

resolve_cheatsheet() {
    local requested=$1
    local root target

    if [[ $requested == /* ]]; then
        notify_error "Erwartet wird ein relativer Pfad: $requested"
        return 1
    fi
    if [[ ! -d $sheets_dir ]]; then
        notify_error "Verzeichnis nicht gefunden: $sheets_dir"
        return 1
    fi

    root=$(realpath -e -- "$sheets_dir")
    if ! target=$(realpath -e -- "$root/$requested"); then
        notify_error "Cheatsheet nicht gefunden: $requested"
        return 1
    fi
    if [[ $target != "$root/"* || ! -f $target || ! -r $target ]]; then
        notify_error "Ungültiges Cheatsheet außerhalb des Verzeichnisses: $requested"
        return 1
    fi

    printf '%s\n' "$target"
}

main() {
    local dry_run=0
    if [[ ${1:-} == --dry-run ]]; then
        dry_run=1
        shift
    fi
    if [[ $# -ne 1 || ${1:-} == --help || ${1:-} == -h ]]; then
        usage
        [[ $# -eq 1 ]] && return 0
        return 2
    fi

    load_configuration

    local target extension
    target=$(resolve_cheatsheet "$1") || return 1
    extension=${target##*.}
    extension=${extension,,}

    local -a command
    case $extension in
    md)
        require_command "$terminal"
        require_command "$md_viewer"
        command=("$terminal" -e "$md_viewer" "$target")
        ;;
    txt)
        require_command "$terminal"
        require_command "$text_viewer"
        command=("$terminal" -e "$text_viewer" "$target")
        ;;
    pdf | html | htm | png | jpg | jpeg)
        require_command "$desktop_opener"
        command=("$desktop_opener" "$target")
        ;;
    *)
        notify_error "Nicht unterstützter Dateityp: .$extension"
        return 1
        ;;
    esac

    if ((dry_run)); then
        print_command "${command[@]}"
        return 0
    fi

    setsid -f "${command[@]}" >/dev/null 2>&1
}

main "$@"
