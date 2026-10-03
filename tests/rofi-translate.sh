#!/usr/bin/env bash
# Regression checks for translation commands and consecutive input.

set -o errexit -o nounset -o pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
launcher="$repository_root/bin/rofi-translate.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

cat >"$fixture/rofi" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
count=0
[[ -r $ROFI_TEST_STATE ]] && read -r count <"$ROFI_TEST_STATE"
case $count in
0) printf 'hello world\n' ;;
1) printf 'I would like a cup of tea.\n' ;;
2) printf 'Das Wetter ist heute schön.\n' ;;
*) printf '%s\n' "${ROFI_TEST_ACTION:-Schließen}" ;;
esac
printf '%s\n' "$*" >>"$ROFI_TEST_STATE-args"
printf '%s\n' "$((count + 1))" >"$ROFI_TEST_STATE"
EOF

cat >"$fixture/trans" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ROFI_TEST_STATE-trans"
if [[ " $* " == *' --identify '* ]]; then
    case ${*: -1} in
    'Das Wetter ist heute schön.') printf 'Code                  de\n' ;;
    *) printf 'Code                  en\n' ;;
    esac
    exit 0
fi
case ${*: -1} in
'hello world') printf 'Hallo Welt\n' ;;
'I would like a cup of tea.') printf 'Ich möchte eine Tasse Tee.\n' ;;
'Das Wetter ist heute schön.')
    [[ " $* " == *' --target=en '* && " $* " == *' --source=de '* ]] || exit 1
    printf 'The weather is nice today.\n'
    ;;
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
brief=$(PATH="$fixture:$PATH" ROFI_TEST_STATE="$fixture/dry" \
    "$launcher" --dry-run brief "hello world")
german=$(PATH="$fixture:$PATH" ROFI_TEST_STATE="$fixture/dry" \
    "$launcher" --dry-run brief "Das Wetter ist heute schön.")
verbose=$(ROFI_TRANSLATE_TARGET=et "$launcher" --dry-run verbose "hello")
[[ $brief == *'--target=de'* && $brief == *'--source=en'* ]]
[[ $brief == *'--engine google'* && $brief == *'--brief'* ]]
[[ $brief == *'hello\ world'* ]]
[[ $german == *'--target=en'* && $german == *'--source=de'* ]]
[[ $verbose == *'--target=et'* && $verbose != *'--brief'* ]]

PATH="$fixture:$PATH" \
    ROFI_TEST_STATE="$fixture/rofi-state" \
    ROFI_TRANSLATE_HISTORY="$fixture/history" \
    "$launcher"

expected_history=$'#\thello world\tHallo Welt\n#\tI would like a cup of tea.\tIch möchte eine Tasse Tee.\n#\tDas Wetter ist heute schön.\tThe weather is nice today.'
[[ $(<"$fixture/history") == "$expected_history" ]]
[[ $(<"$fixture/rofi-state") == 4 ]]
grep -q 'EN → DE' "$fixture/rofi-state-args"
grep -q 'DE → EN' "$fixture/rofi-state-args"
grep -q -- '--target=de.*--source=en.*hello world' "$fixture/rofi-state-trans"
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
[[ $(<"$fixture/Kopieren-state-clipboard") == 'The weather is nice today.' ]]
[[ $(<"$fixture/Vorlesen-state-speech") == '-f trans --source=de --target=en --speak -- Das Wetter ist heute schön.' ]]

# A sequence-driven fixture covers correction, detection failure and overrides.
cat >"$fixture/rofi" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
count=0
[[ -r $ROFI_TEST_STATE ]] && read -r count <"$ROFI_TEST_STATE"
sed -n "$((count + 1))p" "$ROFI_TEST_SEQUENCE"
printf '%s\n' "$*" >>"$ROFI_TEST_STATE-args"
printf '%s\n' "$((count + 1))" >"$ROFI_TEST_STATE"
EOF
cat >"$fixture/trans" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ROFI_TEST_STATE-trans"
if [[ " $* " == *' --identify '* ]]; then
    [[ ${ROFI_TEST_DETECTION:-en} != failure ]] || exit 1
    if [[ ${ROFI_TEST_DETECTION:-en} == secondary && " $* " == *' --engine google '* ]]; then
        exit 1
    fi
    printf 'Code                  %s\n' "${ROFI_TEST_LANGUAGE:-en}"
    exit 0
fi
case " $* " in
*' --target=de '*) printf 'Deutsch\n' ;;
*' --target=en '*) printf 'English\n' ;;
*' --target=et '*) printf 'Eesti\n' ;;
*) exit 1 ;;
esac
EOF

printf '%s\n' 'Gift' 'Richtung wechseln' 'hello' 'Schließen' >"$fixture/switch-sequence"
PATH="$fixture:$PATH" ROFI_TEST_STATE="$fixture/switch" \
    ROFI_TEST_SEQUENCE="$fixture/switch-sequence" \
    ROFI_TRANSLATE_HISTORY="$fixture/switch-history" "$launcher"
[[ $(<"$fixture/switch-history") == $'#\tGift\tDeutsch\n#\tGift\tEnglish\n#\thello\tDeutsch' ]]
[[ $(grep -c -- '--identify' "$fixture/switch-trans") == 2 ]]

printf '%s\n' 'Hallo' 'Deutsch → Englisch' 'Schließen' >"$fixture/failure-sequence"
PATH="$fixture:$PATH" ROFI_TEST_STATE="$fixture/failure" ROFI_TEST_DETECTION=failure \
    ROFI_TEST_SEQUENCE="$fixture/failure-sequence" \
    ROFI_TRANSLATE_HISTORY="$fixture/failure-history" "$launcher"
[[ $(<"$fixture/failure-history") == $'#\tHallo\tEnglish' ]]
grep -q 'Sprache nicht eindeutig erkannt' "$fixture/failure-args"

PATH="$fixture:$PATH" ROFI_TEST_STATE="$fixture/unknown" ROFI_TEST_LANGUAGE=ja \
    ROFI_TEST_SEQUENCE="$fixture/failure-sequence" \
    ROFI_TRANSLATE_HISTORY="$fixture/unknown-history" "$launcher"
[[ $(<"$fixture/unknown-history") == $'#\tHallo\tEnglish' ]]

printf '%s\n' 'Hallo' >"$fixture/cancel-sequence"
PATH="$fixture:$PATH" ROFI_TEST_STATE="$fixture/cancel" ROFI_TEST_DETECTION=failure \
    ROFI_TEST_SEQUENCE="$fixture/cancel-sequence" \
    ROFI_TRANSLATE_HISTORY="$fixture/cancel-history" "$launcher"
[[ ! -e $fixture/cancel-history ]]

if PATH="$fixture:$PATH" ROFI_TEST_STATE="$fixture/dry-failure" ROFI_TEST_DETECTION=failure \
    "$launcher" --dry-run brief 'Hallo' 2>"$fixture/dry-error"; then
    printf 'Dry run accepted failed language detection\n' >&2
    exit 1
fi
[[ ! -e $fixture/dry-failure-args ]]

printf '%s\n' 'hello' 'Schließen' >"$fixture/simple-sequence"
PATH="$fixture:$PATH" ROFI_TEST_STATE="$fixture/secondary" ROFI_TEST_DETECTION=secondary \
    ROFI_TEST_SEQUENCE="$fixture/simple-sequence" \
    ROFI_TRANSLATE_HISTORY="$fixture/secondary-history" "$launcher"
[[ $(grep -c -- '--identify' "$fixture/secondary-trans") == 2 ]]
[[ $(<"$fixture/secondary-history") == $'#\thello\tDeutsch' ]]

PATH="$fixture:$PATH" ROFI_TEST_STATE="$fixture/override" ROFI_TRANSLATE_TARGET=et \
    ROFI_TEST_SEQUENCE="$fixture/simple-sequence" \
    ROFI_TRANSLATE_HISTORY="$fixture/override-history" "$launcher"
[[ $(<"$fixture/override-history") == $'#\thello\tEesti' ]]
if grep -q -- '--identify' "$fixture/override-trans"; then
    printf 'Explicit target unexpectedly triggered language detection\n' >&2
    exit 1
fi

printf 'rofi-translate tests passed\n'
