#!/usr/bin/env sh
# sb-forecast.sh — kompakte Wetteranzeige für Panels (z. B. Lemonbar)
#
# Ausgabe-Format (identisch zu bisher):
#   "爫<Regenwahrscheinlichkeit>% <Tiefstwert>° <Höchstwert>°"
#
# PARAMETER
#   1) LOCATION (optional): Ort/Region wie bei wttr.in (UTF‑8 erlaubt, z. B. "München").
#      Fällt zurück auf DEFAULT_LOCATION.
#   2) "age" (optional, Schalter): Gibt nur das Alter (Minuten) des Cache-Files aus.
#      Nützlich für Statusmeldungen wie: notify-send "Update vor $(sb-forecast.sh München age) min"
#   3) LANG (optional): Sprache gemäß wttr.in (z. B. de, en, fr, ru, …). Default: de.
#      Alternativ kann die Sprache auch per Umgebungsvariable WEATHER_LANG gesetzt werden.
#
# UMGEBUNGSVARIABLEN
#   DEFAULT_LOCATION      — Standard-Ort (Default: "München")
#   WTTRURL               — Basis-URL für wttr (Default: "wttr.in")
#   WEATHERREPORT         — Basispfad/Prefix der Cache-Datei, OHNE Suffix (Default: "$XDG_CACHE_HOME/weather" bzw. "$HOME/.cache/weather")
#   WEATHER_LANG          — Sprache (z. B. "de"). Wird von Param 3 übersteuert. Default: "de"
#   WEATHER_MAX_AGE_MIN   — Maximales Cache-Alter in Minuten. Default: 240 (4h)
#
# FUNKTIONSWEISE
#   - Holt strukturierte Daten von wttr.in im JSON-Format (?format=j1) und cached sie.
#   - Verwendet Cache, solange dieser jünger als WEATHER_MAX_AGE_MIN ist.
#   - Bei "age" wird nur das Alter der Cache-Datei in Minuten ausgegeben.
#   - Robust gegenüber Layout-Änderungen, da JSON statt Text-Kunst ausgewertet wird.
#
# Abhängigkeiten: curl, date, stat, awk, grep, printf, head, sed, sort
# POSIX /bin/sh-kompatibel (keine Bashisms).

DEFAULT_LOCATION="${DEFAULT_LOCATION:-München}"
URL="${WTTRURL:-wttr.in}"
# Basename für Cache-Datei (ohne Suffixe)
WEATHERREPORT="${WEATHERREPORT:-${XDG_CACHE_HOME:-$HOME/.cache}/weather}"
WEATHER_LANG_DEFAULT="${WEATHER_LANG:-de}"
WEATHER_MAX_AGE_MIN="${WEATHER_MAX_AGE_MIN:-240}"

# ---------- Hilfsfunktionen ----------

die() { printf "%s\n" "$*" >&2; exit 1; }

trim() {
    # führende/nachfolgende Leerzeichen entfernen (POSIX)
    # shellcheck disable=SC2001
    echo "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# Cache-Datei-Pfad aus Ort + Sprache erzeugen
cache_path() {
    _loc="$1"
    _lang="$2"
    # Leerzeichen durch Unterstrich ersetzen, Umlaute etc. bleiben (Datei ist UTF‑8)
    _slug=$(printf "%s" "$_loc" | tr ' /' '__')
    printf "%s_%s_%s.json" "$WEATHERREPORT" "$_slug" "$_lang"
}

file_age_minutes() {
    _file="$1"
    if [ -f "$_file" ]; then
        file_mod_time=$(stat -c %Y "$_file" 2>/dev/null || stat -f %m "$_file" 2>/dev/null) || return 0
        current_time=$(date +%s)
        age_seconds=$((current_time - file_mod_time))
        printf "%s" $((age_seconds / 60))
    else
        printf "0"
    fi
}

fetch_json() {
    _loc="$1"
    _lang="$2"
    _out="$3"
    # Hinweis: wttr.in versteht UTF‑8 im Pfad; Sprache via ?lang=xx; JSON via ?format=j1
    # kurze Timeouts, still, Fehlercode auswerten
    curl --max-time 2 --silent --show-error --fail \
         "https://$URL/${_loc}?format=j1&lang=${_lang}" > "$_out".tmp || return 1
    mv -- "$_out".tmp "$_out"
    return 0
}

# JSON auswerten ohne jq: einfache, robuste AWK/grep-Extraktion.
# (wttr.in liefert kleine JSONs, die sich mit grep/awk ausreichend stabil extrahieren lassen)
json_get_first_match_number() {
    # $1: Datei, $2: Regex-Schlüssel (z. B. \"maxtempC\")
    awk -v key="$2" '
        $0 ~ key {
            if (match($0, /[-]?[0-9]+(\.[0-9]+)?/)) {
                print substr($0, RSTART, RLENGTH);
                exit
            }
        }
    ' "$1"
}

# Tages-Max/Min (°C) und Regenwahrscheinlichkeit (%) aus JSON holen.
extract_values() {
    _json="$1"
    # maxtempC/mintempC stehen im ersten "weather"‑Block des Tages
    maxc=$(json_get_first_match_number "$_json" "\"maxtempC\"")
    minc=$(json_get_first_match_number "$_json" "\"mintempC\"")

    # stündliche Regenwahrscheinlichkeiten: chanceofrain
    # wir suchen den höchsten Wert des ersten Tagesblocks
    # einfache Heuristik: die ersten ~24 "hourly" Einträge
    best=0
    count=0
    awk '
        /"chanceofrain"/ {
            if (match($0, /"[0-9][0-9]?[0-9]?"/)) {
                val=substr($0, RSTART+1, RLENGTH-2)+0
                if (val>best) best=val
                count++
                if (count>=24) { print best; exit }
            }
        }
        END { if (count==0) print 0 }
    ' "$_json"
    prcp=$?
}

# Da wir in POSIX sh bleiben wollen, extrahieren wir die drei Werte separat
get_daily_high_c() { json_get_first_match_number "$1" "\"maxtempC\"" ; }
get_daily_low_c()  { json_get_first_match_number "$1" "\"mintempC\"" ; }
get_best_rain_pct_first_day() {
    awk '
        /"chanceofrain"/ {
            if (match($0, /"[0-9][0-9]?[0-9]?"/)) {
                val=substr($0, RSTART+1, RLENGTH-2)+0
                if (val>best) best=val
                count++
                if (count>=24) { print best; exit }
            }
        }
        END {
            if (count==0) print 0
        }
    ' "$1"
}

# ---------- Parameter parsen ----------
location=""
want_age_only="false"
lang="$WEATHER_LANG_DEFAULT"

# Bis zu 3 Parameter flexibel interpretieren:
#  - alles was "age" ist -> age-Modus
#  - alles was 2‑4 Zeichen und nur Buchstaben/Ziffern/-_ ist -> Sprache
#  - erster andere Parameter -> Ort
for arg in "$@"; do
    case "$arg" in
        age) want_age_only="true" ;;
        [A-Za-z][A-Za-z0-9_-][A-Za-z0-9_-]?) lang="$arg" ;;
        *)
            if [ -z "$location" ]; then
                location="$arg"
            else
                # falls der Ort Leerzeichen enthält und in mehreren Args kam
                location="$location $arg"
            fi
        ;;
    esac
done

[ -n "$location" ] || location="$DEFAULT_LOCATION"
location="$(trim "$location")"

cache_file="$(cache_path "$location" "$lang")"

# ---------- age-Modus ----------
if [ "$want_age_only" = "true" ]; then
    file_age_minutes "$cache_file"
    exit 0
fi

# ---------- Cache prüfen / ggf. holen ----------
age_min=$(file_age_minutes "$cache_file")
# shellcheck disable=SC2039
# (POSIX: Vergleich rein numerisch)
# Wenn Cache fehlt: age_min=0 -> wir versuchen zu fetchen
need_fetch=0
if [ ! -s "$cache_file" ]; then
    need_fetch=1
elif [ "$age_min" -ge "$WEATHER_MAX_AGE_MIN" ]; then
    need_fetch=1
fi

if [ "$need_fetch" -eq 1 ]; then
    if ! fetch_json "$location" "$lang" "$cache_file"; then
        # Wenn Fetch fehlschlägt und kein Cache vorhanden ist -> leer
        if [ ! -s "$cache_file" ]; then
            # Sicherer Fallback
            printf "爫0%% ?° ?°"
            exit 0
        fi
        # sonst: alten Cache weiterverwenden
    fi
fi

# ---------- Werte extrahieren ----------
maxc=$(get_daily_high_c "$cache_file")
minc=$(get_daily_low_c  "$cache_file")
rain=$(get_best_rain_pct_first_day "$cache_file")

# Fallbacks falls leer
[ -n "$maxc" ] || maxc="?"
[ -n "$minc" ] || minc="?"
[ -n "$rain" ] || rain="0"

# ---------- Ausgabe ----------
# Icons beibehalten wie im Original:
#   Regen: 爫   Tief:    Hoch: 
# (Nerd-Font ggf. vorausgesetzt)
printf "爫%s%% %s° %s°" "$rain" "$minc" "$maxc"
