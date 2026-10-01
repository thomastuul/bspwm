#!/usr/bin/env bash
# Regression checks for translation commands and consecutive input.

set -o errexit -o nounset -o pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
launcher="$repository_root/bin/rofi-translate.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

brief=$("$launcher" --dry-run brief "hello world")
verbose=$(ROFI_TRANSLATE_TARGET=et "$launcher" --dry-run verbose "hello")

[[ $brief == *'--target=de'* ]]
[[ $brief == *'--engine google'* ]]
[[ $brief == *'--brief'* ]]
[[ $brief == *'hello\ world'* ]]

[[ $verbose == *'--target=et'* ]]
[[ $verbose != *'--brief'* ]]

cat >"$fixture/rofi" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
count=0
[[ -r $ROFI_TEST_STATE ]] && read -r count <"$ROFI_TEST_STATE"
case $count in
0) printf 'hello world\n' ;;
1) printf 'I would like a cup of tea.\n' ;;
2) printf 'The weather is nice today.\n' ;;
*) printf '%s\n' "${ROFI_TEST_ACTION:-Schließen}" ;;
esac
printf '%s\n' "$*" >>"$ROFI_TEST_STATE-args"
printf '%s\n' "$((count + 1))" >"$ROFI_TEST_STATE"
EOF

cat >"$fixture/trans" <<'EOF'
#!/usr/bin/env bash
case ${*: -1} in
'hello world') printf 'Hallo Welt\n' ;;
'I would like a cup of tea.') printf 'Ich möchte eine Tasse Tee.\n' ;;
'The weather is nice today.') printf 'Das Wetter ist heute schön.\n' ;;
*) exit 1 ;;
esac
EOF

cat >"$fixture/xclip" <<'EOF'
#!/usr/bin/env bash
cat >"$ROFI_TEST_STATE-clipboard"
EOF

cat >"$fixture/setsid" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$ROFI_TEST_STATE-speech"
EOF

chmod +x "$fixture/rofi" "$fixture/trans" "$fixture/xclip" "$fixture/setsid"
PATH="$fixture:$PATH" \
    ROFI_TEST_STATE="$fixture/rofi-state" \
    ROFI_TRANSLATE_HISTORY="$fixture/history" \
    "$launcher"

expected_history=$'#\thello world\tHallo Welt\n#\tI would like a cup of tea.\tIch möchte eine Tasse Tee.\n#\tThe weather is nice today.\tDas Wetter ist heute schön.'
[[ $(<"$fixture/history") == "$expected_history" ]]
[[ $(<"$fixture/rofi-state") == 4 ]]
if grep -q -- '-no-custom' "$fixture/rofi-state-args"; then
    printf 'Result dialog rejects new translation input\n' >&2
    exit 1
fi

for action in Kopieren Vorlesen; do
    PATH="$fixture:$PATH" \
        ROFI_TEST_ACTION="$action" \
        ROFI_TEST_STATE="$fixture/$action-state" \
        ROFI_TRANSLATE_HISTORY="$fixture/$action-history" \
        "$launcher"
    [[ $(<"$fixture/$action-history") == "$expected_history" ]]
done
[[ $(<"$fixture/Kopieren-state-clipboard") == 'Das Wetter ist heute schön.' ]]
[[ $(<"$fixture/Vorlesen-state-speech") == '-f trans --target=de --speak -- The weather is nice today.' ]]

printf 'rofi-translate tests passed\n'
