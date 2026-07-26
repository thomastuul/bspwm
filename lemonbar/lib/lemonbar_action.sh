#!/usr/bin/env bash

# Build one shell-safe command and escape Lemonbar's action delimiter.
lemonbar_action() {
    local argument quoted action=""

    for argument in "$@"; do
        printf -v quoted '%q' "$argument"
        action+="${action:+ }${quoted}"
    done

    printf '%s' "${action//:/\\:}"
}
