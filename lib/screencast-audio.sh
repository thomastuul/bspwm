#!/usr/bin/env bash
# Select recording inputs without changing microphone gain or default devices.

screencast_effects_connected() {
    local source=$1
    pw-dump 2>/dev/null | jq -e --arg source "$source" '
        [.[] | select(.type == "PipeWire:Interface:Node")] as $nodes
        | [$nodes[] | select(.info.props["node.name"] == $source) | .id][0] as $from
        | [$nodes[] | select(.info.props["node.name"] == "easyeffects_source") | .id][0] as $to
        | [.[] | select(.type == "PipeWire:Interface:Link")
           | select(.info.state != "error" and .info.state != "unlinked")
           | [.info["output-node-id"], .info["input-node-id"]]] as $edges
        | select($from != null and $to != null)
        | reduce range(0; ($nodes | length)) as $step ([$from];
            . as $seen
            | ($seen + [$edges[] | select(.[0] as $id | $seen | index($id)) | .[1]])
            | unique)
        | index($to) != null
    ' >/dev/null 2>&1
}

# These values are consumed by bin/screencast.sh and the selection tests.
# shellcheck disable=SC2034
screencast_select_audio() {
    local sources selection pattern probe_pid attempt connected=false
    local -a internal=()
    source_name=''
    audio_label=''
    audio_port=''
    audio_previous_port=''
    audio_physical_source=''

    [[ ${SCREENCAST_AUDIO:-auto} != none ]] || return 0
    command -v pactl >/dev/null || return 0
    sources=$(LC_ALL=C pactl list short sources 2>/dev/null || true)
    for pattern in FIFINE Poly_Studio_P5; do
        source_name=$(awk -v pattern="$pattern" '$2 ~ pattern && $2 !~ /\.monitor$/ {print $2; exit}' <<< "$sources")
        if [[ -n $source_name ]]; then
            audio_label=$source_name
            return 0
        fi
    done

    # JSON metadata distinguishes built-in microphones from onboard line inputs.
    command -v jq >/dev/null || return 0
    sources=$(LC_ALL=C pactl --format=json list sources 2>/dev/null) || return 0
    selection=$(jq -cer '
        [ .[]
          | select(.properties["device.class"] != "monitor")
          | select(.name | endswith(".monitor") | not)
          | [(.ports // [])[]
             | select(.name | test("internal[-_]mic|dmic"; "i"))
             | select(.availability != "not available" and .availability != "no")]
            as $ports
          | if ($ports | length) > 0 then
                {source: .name, port: $ports[0].name, previous: (.active_port // "")}
            elif .properties["device.form_factor"] == "internal"
                 and ((.ports // []) | length) == 0 then
                {source: .name, port: "", previous: ""}
            else empty end
        ][0] // empty
    ' <<< "$sources" 2>/dev/null) || return 0
    mapfile -t internal < <(jq -r '.source, .port, .previous' <<< "$selection")
    source_name=${internal[0]}
    audio_physical_source=$source_name
    audio_port=${internal[1]}
    audio_previous_port=${internal[2]}
    audio_label='Internes Mikrofon (direkt, ohne EasyEffects)'

    # A virtual source alone does not prove that EasyEffects uses this microphone.
    command -v pw-dump >/dev/null || return 0
    jq -e 'any(.[]; .name == "easyeffects_source" and .mute != true)' \
        <<< "$sources" >/dev/null || return 0
    if screencast_effects_connected "$source_name"; then
        connected=true
    elif command -v parec >/dev/null && command -v timeout >/dev/null; then
        # EasyEffects disconnects its input chain while idle. Briefly open its
        # source to verify the real route; discard audio and bound probe lifetime.
        timeout 2 parec --device=easyeffects_source --raw </dev/null >/dev/null 2>&1 9>&- &
        probe_pid=$!
        for ((attempt = 0; attempt < 10; attempt++)); do
            if screencast_effects_connected "$source_name"; then
                connected=true
                break
            fi
            kill -0 "$probe_pid" 2>/dev/null || break
            sleep 0.1
        done
        kill "$probe_pid" 2>/dev/null || true
        wait "$probe_pid" 2>/dev/null || true
    fi
    if [[ $connected == true ]]; then
        source_name=easyeffects_source
        audio_label='Internes Mikrofon über EasyEffects'
    fi
}

screencast_restore_audio_port() {
    local statefile=$1 current
    local -a saved=()
    [[ -f $statefile ]] || return 0
    mapfile -t saved < "$statefile"
    if ((${#saved[@]} != 3)); then
        printf 'Ungültiger Mikrofonanschluss-Status: %s\n' "$statefile" >&2
        return 1
    fi
    # A missing device or a manually changed port must not block stopping.
    if command -v pactl >/dev/null && command -v jq >/dev/null; then
        current=$(LC_ALL=C pactl --format=json list sources 2>/dev/null |
            jq -r --arg source "${saved[0]}" '.[] | select(.name == $source) | .active_port // ""') || return 1
        if [[ $current == "${saved[2]}" ]]; then
            pactl set-source-port "${saved[0]}" "${saved[1]}" || return 1
        fi
    fi
    rm -f -- "$statefile"
}
