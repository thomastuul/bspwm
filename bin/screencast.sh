#!/usr/bin/env bash
# Toggle a screen recording, preferring USB microphones before built-in audio.
set -euo pipefail
umask 077

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/screencast-audio.sh
source "$script_dir/../lib/screencast-audio.sh"

runtime=${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR ist nicht gesetzt}
pidfile="$runtime/screencast.pid"
silentfile="$runtime/screencast.silent"
fileinfo="$runtime/screencast.file"
portfile="$runtime/screencast.port"
logfile="$runtime/screencast.log"
exec 9>"$runtime/screencast.lock"
flock -n 9 || exit 0

hint() {
    if [[ -t 1 ]]; then
        printf '%s\n' "$*"
    fi
}

fail() {
    printf '%s\n' "$*" >&2
    if command -v notify-send >/dev/null; then
        notify-send 'Screencast konnte nicht gestartet werden' "$*" || true
    fi
    exit 1
}

# Stopping must work even if the microphone was disconnected meanwhile.
if [[ -f "$pidfile" ]]; then
    read -r pid < "$pidfile" || pid=''
    if [[ "$pid" =~ ^[0-9]+$ ]] && [[ $(ps -p "$pid" -o comm=) == ffmpeg ]]; then
        kill -INT "$pid"
        for ((attempt = 0; attempt < 100; attempt++)); do
            state=$(ps -p "$pid" -o stat= || true)
            [[ -z "$state" || "$state" == Z* ]] && break
            sleep 0.1
        done
        if [[ -n "$state" && "$state" != Z* ]]; then
            fail 'Aufnahme wird noch beendet. Bitte erneut versuchen.'
        fi
        file=$(cat "$fileinfo" 2>/dev/null || true)
        if [[ -s "$file" ]]; then
            hint "Aufnahme gespeichert: $file"
        else
            hint "Keine Aufnahmedatei vorhanden; Diagnose: $logfile"
        fi
    else
        hint 'Veralteten Aufnahmestatus entfernt.'
    fi
    screencast_restore_audio_port "$portfile" || fail 'Vorheriger Mikrofonanschluss konnte nicht wiederhergestellt werden.'
    rm -f -- "$pidfile" "$silentfile" "$fileinfo"
    exit 0
fi

command -v ffmpeg >/dev/null || fail 'FFmpeg fehlt.'
screencast_restore_audio_port "$portfile" || fail 'Vorheriger Mikrofonanschluss konnte nicht wiederhergestellt werden.'
screencast_select_audio

size=$(xdpyinfo 2>/dev/null | awk '/dimensions:/ && !found {print $2; found=1}') || fail 'Bildschirm nicht erreichbar.'
[[ "$size" =~ ^[0-9]+x[0-9]+$ ]] || fail 'Bildschirmgröße nicht ermittelbar.'
folder="$HOME/Videos"
mkdir -p -- "$folder"
file="$folder/screencast-$(date +%d-%m-%Y-%H-%M-%S-%N).mkv"
if [[ -n $audio_port && -n $audio_previous_port && $audio_port != "$audio_previous_port" ]]; then
    # Restore only this temporary port change, including after a failed start.
    printf '%s\n' "$audio_physical_source" "$audio_previous_port" "$audio_port" > "$portfile"
    trap 'screencast_restore_audio_port "$portfile"' EXIT
    pactl set-source-port "$audio_physical_source" "$audio_port" || fail 'Internes Mikrofon konnte nicht ausgewählt werden.'
fi
args=(-nostdin -hide_banner -loglevel warning -n -probesize 32 -analyzeduration 0 -f x11grab -framerate 30 -video_size "$size" -i "${DISPLAY:-:0.0}")
if [[ -n "$source_name" ]]; then
    args+=(-itsoffset 0.3 -probesize 32 -analyzeduration 0 -f pulse -i "$source_name" -ac 2 -c:a pcm_s16le)
    rm -f -- "$silentfile"
else
    args+=(-an)
    : > "$silentfile"
    hint 'Kein Mikrofon erkannt – Bildschirmaufnahme läuft ohne Ton.'
fi
args+=(-c:v libx264 -pix_fmt yuv420p -preset ultrafast -crf 0 -threads 0 "$file")
ffmpeg "${args[@]}" >"$logfile" 2>&1 9>&- </dev/null &
pid=$!
# Publish the active marker only after FFmpeg has opened its output.
ready=false
for ((attempt = 0; attempt < 50; attempt++)); do
    kill -0 "$pid" 2>/dev/null || break
    if [[ -e "$file" ]]; then
        sleep 0.3
        kill -0 "$pid" 2>/dev/null || break
        ready=true
        break
    fi
    sleep 0.1
done
if [[ "$ready" != true ]]; then
    kill -INT "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    rm -f -- "$silentfile"
    fail "Aufnahme konnte nicht gestartet werden. Diagnose: $logfile"
fi
printf '%s\n' "$file" > "$fileinfo"
printf '%s\n' "$pid" > "$pidfile"
trap - EXIT
hint "Aufnahme gestartet: $file"
if [[ -n $source_name ]]; then
    hint "Audio: $audio_label"
    if command -v notify-send >/dev/null; then
        notify-send 'Bildschirmaufnahme gestartet' "Audio: $audio_label" || true
    fi
fi
