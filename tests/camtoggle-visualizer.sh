#!/usr/bin/env bash
# Verify the camera preview builds the expected mpv visualization arguments.

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly ROOT_DIR
readonly SCRIPT="$ROOT_DIR/bin/camtoggle.sh"
TEMP_DIR=$(mktemp -d)
readonly TEMP_DIR
trap 'rm -rf -- "$TEMP_DIR"' EXIT

mkdir -p "$TEMP_DIR/bin" "$TEMP_DIR/runtime"
cat >"$TEMP_DIR/bin/mpv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$CAMERA_PREVIEW_TEST_ARGS"
EOF
chmod +x "$TEMP_DIR/bin/mpv"

run_preview() {
    local name=$1
    shift

    CAMERA_PREVIEW_TEST_ARGS="$TEMP_DIR/$name.args" \
        PATH="$TEMP_DIR/bin:$PATH" \
        XDG_RUNTIME_DIR="$TEMP_DIR/runtime" \
        CAMERA_PREVIEW_PREFERRED="" \
        "$@" "$SCRIPT"
}

run_preview default env

grep -Fx -- '--mute=yes' "$TEMP_DIR/default.args" >/dev/null
grep -Fx -- '--aid=no' "$TEMP_DIR/default.args" >/dev/null
grep -Fx -- '--audio-file=av://pulse:default' "$TEMP_DIR/default.args" >/dev/null
grep -F -- '[aid1]asetpts=PTS-STARTPTS' "$TEMP_DIR/default.args" >/dev/null
grep -F -- '[vid1]setpts=PTS-STARTPTS' "$TEMP_DIR/default.args" >/dev/null
grep -F -- 'showspectrum=' "$TEMP_DIR/default.args" >/dev/null

printf 'PASS: default camera preview enables the spectrum visualizer\n'

run_preview none env CAMERA_PREVIEW_VISUALIZER=none

grep -Fx -- '--no-audio' "$TEMP_DIR/none.args" >/dev/null
if grep -F -- '--audio-file=' "$TEMP_DIR/none.args" >/dev/null ||
    grep -F -- '--lavfi-complex=' "$TEMP_DIR/none.args" >/dev/null; then
    printf 'FAIL: none mode unexpectedly configured a visualizer\n' >&2
    exit 1
fi

printf 'PASS: none mode preserves the plain, audio-free preview\n'

run_preview wave env \
    CAMERA_PREVIEW_VISUALIZER=wave \
    CAMERA_PREVIEW_AUDIO_SOURCE=test-microphone

grep -Fx -- '--mute=yes' "$TEMP_DIR/wave.args" >/dev/null
grep -Fx -- '--audio-file=av://pulse:test-microphone' "$TEMP_DIR/wave.args" >/dev/null
grep -F -- 'showwaves=' "$TEMP_DIR/wave.args" >/dev/null

printf 'PASS: wave mode uses the selected audio source\n'

run_preview brightness env CAMERA_PREVIEW_VISUALIZER=brightness

grep -Fx -- '--no-audio' "$TEMP_DIR/brightness.args" >/dev/null
grep -F -- 'signalstats' "$TEMP_DIR/brightness.args" >/dev/null
grep -F -- 'drawgraph=' "$TEMP_DIR/brightness.args" >/dev/null
if grep -F -- '--audio-file=' "$TEMP_DIR/brightness.args" >/dev/null; then
    printf 'FAIL: brightness mode unexpectedly opened an audio source\n' >&2
    exit 1
fi

printf 'PASS: brightness mode visualizes video luminance without audio\n'

run_preview hud env CAMERA_PREVIEW_VISUALIZER=hud

grep -Fx -- '--mute=yes' "$TEMP_DIR/hud.args" >/dev/null
grep -Fx -- "--external-file=$ROOT_DIR/assets/camera-hud-overlay.png" "$TEMP_DIR/hud.args" >/dev/null
grep -F -- '[vid2]' "$TEMP_DIR/hud.args" >/dev/null
grep -F -- 'showvolume=' "$TEMP_DIR/hud.args" >/dev/null
grep -F -- 'c=0x78ff6a' "$TEMP_DIR/hud.args" >/dev/null

printf 'PASS: hud mode combines the transparent HUD with an audio level meter\n'

run_preview hud-spectrum env CAMERA_PREVIEW_VISUALIZER=hud-spectrum

grep -Fx -- '--mute=yes' "$TEMP_DIR/hud-spectrum.args" >/dev/null
grep -Fx -- "--external-file=$ROOT_DIR/assets/camera-hud-overlay.png" "$TEMP_DIR/hud-spectrum.args" >/dev/null
grep -F -- '[vid2]' "$TEMP_DIR/hud-spectrum.args" >/dev/null
grep -F -- 'showspectrum=s=210x32' "$TEMP_DIR/hud-spectrum.args" >/dev/null
grep -F -- '[hudspectrum]' "$TEMP_DIR/hud-spectrum.args" >/dev/null
grep -F -- 'overlay=x=(W-w)/2:y=H-h-16[vo]' "$TEMP_DIR/hud-spectrum.args" >/dev/null

printf 'PASS: hud-spectrum mode combines the transparent HUD with a spectrum tray\n'

run_preview invalid env CAMERA_PREVIEW_VISUALIZER=unknown

grep -F -- 'showspectrum=' "$TEMP_DIR/invalid.args" >/dev/null

printf 'PASS: unknown modes fall back to the spectrum visualizer\n'
