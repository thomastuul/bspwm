#!/usr/bin/env bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace # Trace the execution of the script (debug)
fi
set -o xtrace # Trace the execution of the script (debug)

set -o errexit  # Exit on most errors (see the manual)
set -o nounset  # Disallow expansion of unset variables
set -o pipefail # Use last non-zero exit code in a pipeline
# Enable errtrace or the error trap handler will not work as expected
set -o errtrace # Ensure the error trap handler is inherited
# shellcheck disable=SC1090
if [[ -n "${BASH_ENV:-}" && -r "$BASH_ENV" ]]; then
    # shellcheck source=../lib/logging_env.sh
    source "$BASH_ENV"
else
    exit 1
fi

# shellcheck disable=SC2154
title_fifo="$tmp_dir/lemonbar_title.fifo"

# wait for fifo file to be established
if [[ ! -p "$title_fifo" ]]; then
    printf ""
else
    if ! read -t 0.1 -r line <"$title_fifo"; then
        exit 0 # FIFO zu → regulär beenden
    fi
    printf "%s" "$line"
fi

# vim: syntax=bash
