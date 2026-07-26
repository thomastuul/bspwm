#!/usr/bin/env bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace # Trace the execution of the script (debug)
fi

set -o errexit  # Exit on most errors (see the manual)
set -o nounset  # Disallow expansion of unset variables
set -o pipefail # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
set -o errtrace # Ensure the error trap handler is inherited

# shellcheck disable=SC1091
source "$LEMONDIR/config.sh"
# shellcheck source=../lib/lemonbar_action.sh
source "$LEMONDIR/lib/lemonbar_action.sh"
# shellcheck disable=SC1090
if [[ -n "${BASH_ENV:-}" && -r "$BASH_ENV" ]]; then
    # shellcheck source=../lib/logging_env.sh
    source "$BASH_ENV"
else
    exit 1
fi

name=""

run=$(lemonbar_action "$HOME/.config/bspwm/rofi/powermenu/powermenu.sh")

power="%{A:${run}:}%{F$COLOR_DEFAULT_FG}%{B$COLOR_DEFAULT_BG}$PADDING${name}$PADDING%{B-}%{F-}%{A}"

printf "%s" "$power"

# vim: syntax=bash
