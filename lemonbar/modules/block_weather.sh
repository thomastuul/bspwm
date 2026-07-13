#!/usr/bin/env bash
#
# block_weather.sh — unified weather module for Lemonbar/BSPWM
#
# Features
# - JSON parsing: precipitation probability (max of next ~24h in 3h steps), min/max daily temperature (°C)
# - Caching in ~/.cache: JSON and PNG (3-day forecast)
# - Parameters:
#     --location, -l  location (default: "München")
#     --age, -a       max cache age (default: "30m")
#     --language, -L  language (default: "de")
#     --print-age     print age of JSON cache in minutes
#     --open          3-day forecast (PNG) open
#     --lemonbar      output formatted for Lemonbar (colors, clicks)
#     --help, -h      help
# -----------------------------------------------------------------------------
set -o errexit -o nounset -o pipefail

# shellcheck disable=SC1091
source "$LEMONDIR/config.sh"
# shellcheck disable=SC1090
if [[ -n "${BASH_ENV:-}" && -r "$BASH_ENV" ]]; then
    # shellcheck source=../lib/logging_env.sh
    source "$BASH_ENV"
else
    printf "%s\n" "BASH_ENV not found"
    exit 1
fi

DEFAULT_LOCATION="${DEFAULT_LOCATION:-München}"
DEFAULT_LANG="${WEATHER_LANG:-de}"
DEFAULT_MAX_AGE="${WEATHER_MAX_AGE:-30m}"
DEFAULT_IMAGE_MAX_AGE="${WEATHER_IMAGE_MAX_AGE:-1h}"
WTTR_BASE="${WTTRURL:-https://wttr.in}"

XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
WEATHER_CACHE_DIR="${WEATHERREPORT:-$XDG_CACHE_HOME/weather}"

die() {
    printf '%s\n' "block_weather: $*" >&2
    exit 1
}

dur_to_seconds() {
    local d="${1:-}"
    [[ -z "$d" ]] && {
        echo 0
        return
    }
    if [[ "$d" =~ ^[0-9]+$ ]]; then
        echo "$d"
        return
    fi
    local num unit
    num="${d//[!0-9]/}"
    unit="${d//[0-9]/}"
    case "$unit" in
    s | '') echo "$num" ;;
    m) echo $((num * 60)) ;;
    h) echo $((num * 3600)) ;;
    d) echo $((num * 86400)) ;;
    *) echo 14400 ;; # fallback 4h on unknown unit ;;
    esac
}

slugify() { printf '%s' "$1" | tr ' /' '__'; }
url_loc() { printf '%s' "$1" | sed 's/ /+/g'; }

file_age_minutes() {
    local f="$1"
    [[ -f "$f" ]] || {
        echo 1000000000
        return
    }
    local now ts
    now="$(date +%s)"
    ts="$(stat -c %Y -- "$f" 2>/dev/null || stat -f %m -- "$f")"
    local diff=$((now - ts))
    echo $((diff / 60))
}

is_fresh() {
    local f="$1" max_age_sec="$2"
    [[ -f "$f" ]] || return 1
    local now ts
    now="$(date +%s)"
    ts="$(stat -c %Y -- "$f" 2>/dev/null || stat -f %m -- "$f")"
    (((now - ts) <= max_age_sec))
}

fetch_json_if_needed() {
    local loc="$1" lang="$2" max_age_sec="$3" json_path="$4"
    if ! is_fresh "$json_path" "$max_age_sec"; then
        mkdir -p -- "$(dirname -- "$json_path")"
        local enc_loc
        enc_loc="$(url_loc "$loc")"
        # tolerant: bei Fehler kein Exit, keine Ausgabe
        if curl -fsSL --connect-timeout 3 --max-time 15 "${WTTR_BASE}/${enc_loc}?format=j1&lang=${lang}" \
            -o "$json_path.tmp" 2>/dev/null; then
            mv -f -- "$json_path.tmp" "$json_path"
        else
            rm -f -- "$json_path.tmp" 2>/dev/null || true
            return 1
        fi
    fi
}

format_minutes_hm() {
    # $1: minutes (integer). Prints "Mmin" below one hour, else "Hh Mmin".
    local m="${1:-0}"
    if [[ "$m" -lt 0 ]]; then m=0; fi

    local h=$((m / 60))
    local mm=$((m % 60))

    if ((h == 0)); then
        printf '%dmin' "$mm"
    else
        printf '%dh %dmin' "$h" "$mm"
    fi
}

fetch_png_if_needed() {
    local loc="$1" lang="$2" max_age_sec="$3" png_path="$4"
    local enc_loc url tmp_path

    if ! is_fresh "$png_path" "$max_age_sec"; then
        mkdir -p -- "$(dirname -- "$png_path")"
        enc_loc="$(url_loc "$loc")"
        url="https://v2.wttr.in/${enc_loc}.png?lang=${lang}&m&2"
        tmp_path="${png_path}.${BASHPID}.tmp"

        # Publish only complete downloads and retain an existing stale image.
        if ! curl -fsSL --connect-timeout 3 --max-time 15 "$url" \
            -o "$tmp_path"; then
            rm -f -- "$tmp_path" 2>/dev/null || true
            return 1
        fi

        mv -f -- "$tmp_path" "$png_path"
    fi
}

parse_with_jq() {
    local json="$1"
    jq -r '
    .weather[0] as $w
    | [$w.hourly[].chanceofrain | tonumber] | max as $maxR
    | "\($maxR)|\($w.mintempC)|\($w.maxtempC)"
  ' "$json"
}

parse_with_awk() {
    local json="$1"
    awk '
    BEGIN {
      maxRain=0; mint=""; maxt=""; count=0; limit=8;
    }
    /"mintempC"[[:space:]]*:/ && mint=="" {
      if (match($0, /"mintempC"[[:space:]]*:[[:space:]]*"[0-9-]+"/)) {
        v=substr($0, RSTART, RLENGTH); gsub(/[^0-9-]/,"",v); mint=v;
      }
    }
    /"maxtempC"[[:space:]]*:/ && maxt=="" {
      if (match($0, /"maxtempC"[[:space:]]*:[[:space:]]*"[0-9-]+"/)) {
        v=substr($0, RSTART, RLENGTH); gsub(/[^0-9-]/,"",v); maxt=v;
      }
    }
    /"chanceofrain"[[:space:]]*:/ {
      if (match($0, /"[0-9][0-9]?[0-9]?"/)) {
        val=substr($0, RSTART+1, RLENGTH-2)+0
        if (val>maxRain) maxRain=val
        count++
        if (count>=limit) { limit=0 }
      }
    }
    END {
      if (mint=="") mint="?";
      if (maxt=="") maxt="?";
      print maxRain "|" mint "|" maxt
    }
  ' "$json"
}

open_png_viewer() {
    local png="$1"
    local scale="${WEATHER_IMAGE_SCALE:-200}"
    local width height scaled_width scaled_height

    if command -v sxiv >/dev/null 2>&1; then
        if command -v identify >/dev/null 2>&1; then
            width=""
            height=""

            if read -r width height < <(
                identify -format '%w %h' "$png" 2>/dev/null
            ); then
                if [[ "$width" =~ ^[0-9]+$ &&
                    "$height" =~ ^[0-9]+$ &&
                    "$scale" =~ ^[0-9]+$ ]] &&
                    ((scale > 0)); then

                    scaled_width=$((width * scale / 100))
                    scaled_height=$((height * scale / 100))

                    nohup sxiv \
                        -b \
                        -g "${scaled_width}x${scaled_height}" \
                        -z "$scale" \
                        "$png" >/dev/null 2>&1 &

                    return
                fi
            fi
        fi

        # Fallback if the image dimensions or scale are unavailable.
        nohup sxiv -b -s f "$png" >/dev/null 2>&1 &
    elif command -v feh >/dev/null 2>&1; then
        nohup feh "$png" >/dev/null 2>&1 &
    else
        nohup xdg-open "$png" >/dev/null 2>&1 &
    fi
}

LOCATION="$DEFAULT_LOCATION"
LANG="$DEFAULT_LANG"
MAX_AGE_STR="$DEFAULT_MAX_AGE"
DO_OPEN=0
DO_PREFETCH_IMAGE=0
DO_PRINT_AGE=0

print_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Optionen:
  -l, --location  ORT     Ort (Default: "$DEFAULT_LOCATION")
  -a, --age       DAUER   Maximales Cache-Alter (Default: "$DEFAULT_MAX_AGE")
  -L, --language  LANG    Sprache (Default: "$DEFAULT_LANG")
      --print-age         Alter des JSON-Caches in Minuten
      --open              3-Tage-Vorschau öffnen
      --prefetch-image    PNG-Vorschau im Cache aktualisieren
      --lemonbar          Ausgabe formatiert für Lemonbar (Farben, Klicks)
  -h, --help              Diese Hilfe
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    -l | --location)
        LOCATION="${2:-}"
        shift 2
        ;;
    -a | --age)
        MAX_AGE_STR="${2:-}"
        shift 2
        ;;
    -L | --language)
        LANG="${2:-}"
        shift 2
        ;;
    --open)
        DO_OPEN=1
        shift
        ;;
    --prefetch-image)
        DO_PREFETCH_IMAGE=1
        shift
        ;;
    --print-age)
        DO_PRINT_AGE=1
        shift
        ;;
    -h | --help)
        print_help
        exit 0
        ;;
    --)
        shift
        break
        ;;
    -*) die "Unbekannte Option: $1" ;;
    *) die "Unerwartetes Argument: $1" ;;
    esac
done

[[ -n "$LOCATION" ]] || die "Leerer Ort übergeben"
[[ -n "$LANG" ]] || die "Leere Sprache übergeben"
MAX_AGE_SEC="$(dur_to_seconds "$MAX_AGE_STR")"
IMAGE_MAX_AGE_SEC="$(dur_to_seconds "$DEFAULT_IMAGE_MAX_AGE")"

slug="$(slugify "$LOCATION")"
JSON_CACHE="${WEATHER_CACHE_DIR}/${slug}.json"
PNG_CACHE="${WEATHER_CACHE_DIR}/${slug}_3days.png"

if ((DO_PRINT_AGE)); then
    if [[ -f "$JSON_CACHE" ]]; then
        m="$(file_age_minutes "$JSON_CACHE")"
        format_minutes_hm "$m"
    else
        printf '%s' 'unbekannt'
    fi
    exit 0
fi

if ((DO_PREFETCH_IMAGE)); then
    fetch_png_if_needed \
        "$LOCATION" "$LANG" "$IMAGE_MAX_AGE_SEC" "$PNG_CACHE"
    exit $?
fi

if ((DO_OPEN)); then
    if [[ -r "$PNG_CACHE" ]]; then
        open_png_viewer "$PNG_CACHE"
    else
        notify-send "Weather forecast" \
            "The forecast image is not available yet."
    fi
    exit 0
fi

if ! fetch_json_if_needed "$LOCATION" "$LANG" "$MAX_AGE_SEC" "$JSON_CACHE"; then
    # Keep displaying an existing stale cache when wttr.in is unavailable.
    [[ -f "$JSON_CACHE" ]] || exit 0
fi

if command -v jq >/dev/null 2>&1; then
    RAIN_MINMAX="$(parse_with_jq "$JSON_CACHE" 2>/dev/null || true)"
fi
if [[ -z "${RAIN_MINMAX:-}" ]]; then
    RAIN_MINMAX="$(parse_with_awk "$JSON_CACHE")"
fi

RAIN="${RAIN_MINMAX%%|*}"
REST="${RAIN_MINMAX#*|}"
MIN="${REST%%|*}"
MAX="${REST#*|}"

[[ -n "${RAIN:-}" ]] || RAIN="0"
[[ -n "${MIN:-}" ]] || MIN="?"
[[ -n "${MAX:-}" ]] || MAX="?"

# ---- Ausgabe ----------------------------------------------------------------

printf -v run_left \
    '%q --open --location %q --language %q --age %q' \
    "$0" "$LOCATION" "$LANG" "$MAX_AGE_STR"

age_text="$(
    "$0" --print-age \
        --location "$LOCATION" \
        --age "$MAX_AGE_STR"
)"

printf -v run_right \
    'notify-send %q' \
    "Update vor $age_text"

printf '%s\n' \
    "%{A1:$run_left:}%{A3:$run_right:}%{B$COLOR_DEFAULT_BG}%{F$COLOR_WEATHER_FG}%{+u} 爫${RAIN}%% ${MIN}° ${MAX}° %{-u}%{F-}%{B-}%{A}%{A}"
