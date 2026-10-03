#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Translate text through translate-shell with a tracked Rofi interface.
# Reworked from https://github.com/garyparrot/rofi-translate (GPLv3).

set -o errexit -o nounset -o pipefail

BSPWM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bspwm"
ROFI_THEME="$BSPWM_CONFIG_DIR/rofi/themes/translate.rasi"
TRANSLATION_HISTORY=${ROFI_TRANSLATE_HISTORY:-"$HOME/.rofi_trans"}
TARGET_LANGUAGE=${ROFI_TRANSLATE_TARGET:-de}
SOURCE_LANGUAGE=auto
AUTOMATIC_DIRECTION=true
[[ -z ${ROFI_TRANSLATE_TARGET:-} ]] || AUTOMATIC_DIRECTION=false
PRIMARY_ENGINE=${ROFI_TRANSLATE_PRIMARY_ENGINE:-google}
SECONDARY_ENGINE=${ROFI_TRANSLATE_SECONDARY_ENGINE:-bing}
VERBOSE_ENTRY="Ausführlich übersetzen …"
CLEAR_HISTORY_ENTRY="Verlauf leeren …"

notify_error() {
    printf 'rofi-translate: %s\n' "$1" >&2
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "Übersetzung" "$1"
    fi
}

run_rofi() {
    local prompt=$1
    shift
    rofi -no-config -dmenu -i -p "$prompt" -theme "$ROFI_THEME" "$@"
}

history_entries() {
    [[ -r $TRANSLATION_HISTORY ]] || return 0
    awk -F '\t' '
        NF >= 2 {
            text = $2
            sub(/^[[:space:]]+/, "", text)
            sub(/[[:space:]]+$/, "", text)
            if (text != "" && !seen[text]++) print text
        }
    ' "$TRANSLATION_HISTORY" | tac
}

choose_text() {
    local prompt=$1
    local -a entries
    mapfile -t entries < <(history_entries)
    printf '%s\n' "${entries[@]}" | run_rofi "$prompt"
}

choose_request() {
    local prompt="DE ↔ EN"
    [[ $AUTOMATIC_DIRECTION == true ]] || prompt="Text nach $TARGET_LANGUAGE übersetzen"
    {
        printf '%s\n' "$VERBOSE_ENTRY" "$CLEAR_HISTORY_ENTRY"
        history_entries
    } | run_rofi "$prompt"
}

resolve_direction() {
    local text=$1
    local allow_manual=${2:-true}
    local engine identification language choice
    [[ $AUTOMATIC_DIRECTION == true ]] || return 0

    for engine in "$PRIMARY_ENGINE" "$SECONDARY_ENGINE"; do
        if identification=$(timeout 15 trans --no-init --identify --engine "$engine" \
            --no-ansi -- "$text" 2>/dev/null); then
            language=$(awk '$1 == "Code" { print $2; exit }' <<<"$identification")
            case $language in
            de) SOURCE_LANGUAGE=de; TARGET_LANGUAGE=en; return 0 ;;
            en) SOURCE_LANGUAGE=en; TARGET_LANGUAGE=de; return 0 ;;
            esac
        fi
    done

    if [[ $allow_manual == false ]]; then
        notify_error "Die Sprache konnte nicht als Deutsch oder Englisch erkannt werden."
        return 1
    fi
    choice=$(printf '%s\n' "Deutsch → Englisch" "Englisch → Deutsch" | \
        run_rofi "Richtung wählen" -no-custom \
            -mesg "Sprache nicht eindeutig erkannt. Bitte Übersetzungsrichtung wählen.") || return 1
    case $choice in
    "Deutsch → Englisch") SOURCE_LANGUAGE=de; TARGET_LANGUAGE=en ;;
    "Englisch → Deutsch") SOURCE_LANGUAGE=en; TARGET_LANGUAGE=de ;;
    *) return 1 ;;
    esac
}

direction_label() {
    case "$SOURCE_LANGUAGE:$TARGET_LANGUAGE" in
    de:en) printf 'DE → EN\n' ;;
    en:de) printf 'EN → DE\n' ;;
    *) printf 'Übersetzung nach %s\n' "$TARGET_LANGUAGE" ;;
    esac
}

translation_command() {
    local mode=$1
    local engine=$2
    local text=$3
    local -a command=(trans --target="$TARGET_LANGUAGE" --engine "$engine" --no-ansi)
    [[ $AUTOMATIC_DIRECTION == false ]] || command+=(--no-init --source="$SOURCE_LANGUAGE")
    [[ $mode == brief ]] && command+=(--brief)
    command+=(-- "$text")
    printf '%q ' "${command[@]}"
    printf '\n'
}

translate_text() {
    local mode=$1
    local text=$2
    local engine result
    local -a command

    for engine in "$PRIMARY_ENGINE" "$SECONDARY_ENGINE"; do
        command=(trans --target="$TARGET_LANGUAGE" --engine "$engine" --no-ansi)
        [[ $AUTOMATIC_DIRECTION == false ]] || command+=(--no-init --source="$SOURCE_LANGUAGE")
        [[ $mode == brief ]] && command+=(--brief)
        command+=(-- "$text")
        if result=$("${command[@]}" 2>/dev/null) && [[ -n $result ]]; then
            printf '%s\n' "$result"
            return 0
        fi
    done

    notify_error "Die Übersetzung ist mit beiden Diensten fehlgeschlagen."
    return 1
}

update_history() {
    local text=$1
    local result=$2
    local history_dir clean_text clean_result
    history_dir=${TRANSLATION_HISTORY%/*}
    [[ $history_dir == "$TRANSLATION_HISTORY" ]] && history_dir=.
    mkdir -p -- "$history_dir"
    clean_text=${text//$'\t'/ }
    clean_text=${clean_text//$'\n'/ }
    clean_result=${result//$'\t'/ }
    clean_result=${clean_result//$'\n'/ }
    printf '#\t%s\t%s\n' "$clean_text" "$clean_result" >>"$TRANSLATION_HISTORY"
}

copy_result() {
    local result=$1
    if command -v xclip >/dev/null 2>&1; then
        printf '%s' "$result" | xclip -selection clipboard
        return 0
    fi
    notify_error "xclip wurde nicht gefunden."
    return 1
}

speak_text() {
    local text=$1
    setsid -f trans --source="$SOURCE_LANGUAGE" --target="$TARGET_LANGUAGE" --speak -- "$text" \
        >/dev/null 2>&1
}

show_result() {
    local text=$1
    local result=$2
    local mode=$3
    local action
    while true; do
        action="$(
            {
                printf '%s\n' "Kopieren" "Vorlesen" "Schließen"
                [[ $AUTOMATIC_DIRECTION == false ]] || printf '%s\n' "Richtung wechseln"
            } | run_rofi "$(direction_label)" -mesg "$result" \
                    -theme-str 'entry { placeholder: "Weiteren Text eingeben und Enter drücken …"; }'
        )" || return 0

        case $action in
        "Kopieren") copy_result "$result"; return ;;
        "Vorlesen") speak_text "$text"; return ;;
        "Schließen" | "") return 0 ;;
        "Richtung wechseln")
            if [[ $AUTOMATIC_DIRECTION == true ]]; then
                action=$SOURCE_LANGUAGE
                SOURCE_LANGUAGE=$TARGET_LANGUAGE
                TARGET_LANGUAGE=$action
                result=$(translate_text "$mode" "$text") || return 1
                update_history "$text" "$result"
            fi
            ;;
        *)
            text=$action
            resolve_direction "$text" || return 0
            result=$(translate_text "$mode" "$text") || return 1
            update_history "$text" "$result"
            ;;
        esac
    done
}

clear_history() {
    local answer history_dir
    answer="$(
        printf '%s\n' "Abbrechen" "Verlauf leeren" | \
            run_rofi "Übersetzungsverlauf löschen?" -no-custom
    )" || return 0
    [[ $answer == "Verlauf leeren" ]] || return 0
    history_dir=${TRANSLATION_HISTORY%/*}
    [[ $history_dir == "$TRANSLATION_HISTORY" ]] && history_dir=.
    mkdir -p -- "$history_dir"
    : >"$TRANSLATION_HISTORY"
}

interactive() {
    local request mode text result
    request=$(choose_request) || return 0
    [[ -n $request ]] || return 0

    case $request in
    "$VERBOSE_ENTRY")
        mode=verbose
        text=$(choose_text "Text ausführlich übersetzen") || \
            return 0
        ;;
    "$CLEAR_HISTORY_ENTRY")
        clear_history
        return
        ;;
    *)
        mode=brief
        text=$request
        ;;
    esac

    [[ -n $text ]] || return 0
    resolve_direction "$text" || return 0
    result=$(translate_text "$mode" "$text") || return 1
    update_history "$text" "$result"
    show_result "$text" "$result" "$mode"
}

main() {
    command -v trans >/dev/null 2>&1 || {
        notify_error "translate-shell wurde nicht gefunden."
        return 1
    }

    if [[ ${1:-} == --dry-run ]]; then
        [[ $# -eq 3 && ($2 == brief || $2 == verbose) ]] || {
            printf 'Usage: %s --dry-run brief|verbose TEXT\n' "${0##*/}" >&2
            return 2
        }
        resolve_direction "$3" false || return 1
        translation_command "$2" "$PRIMARY_ENGINE" "$3"
        return 0
    fi
    [[ $# -eq 0 ]] || return 2
    command -v rofi >/dev/null 2>&1 || return 1
    interactive
}

main "$@"
