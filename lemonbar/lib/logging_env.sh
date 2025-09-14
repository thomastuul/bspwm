#!/usr/bin/env bash
# Unified, structured logging for all lemonbar scripts.
# Format je Zeile: "YYYY-MM-DD HH:MM:SS | SCRIPT | MESSAGE | RC"
# Erwartet: LOG_FILE ist exportiert. BASH_ENV zeigt auf diese Datei.

set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# Skriptname für Kind-Shells ableiten
__lb_script_name="${script_name:-$(basename -- "${BASH_SOURCE[1]:-${0:-unknown}}")}"

# Logdatei muss vom Parent kommen
: "${LOG_FILE:?LOG_FILE must be exported by parent}"

# Manueller Logger: logging "message" [rc]
logging() {
    local msg="${1-}" rc="${2-0}" ts
    ts="$(date +'%F %T')"
    printf '%s | %s | %s | %s\n' "$ts" "$__lb_script_name" "$msg" "$rc" >>"$LOG_FILE"
}

# stdout/stderr zeilenweise formatieren; stdout=>RC=0, stderr=>RC=1
exec 1> >(
    awk -v n="$__lb_script_name" -v f="$LOG_FILE" '{
        t=strftime("%F %T");
        msg=length($0)?$0:" ";
        printf "%s | %s | %s | 0\n", t, n, msg >> f; fflush(f);
    }'
)
exec 2> >(
    awk -v n="$__lb_script_name" -v f="$LOG_FILE" '{
        t=strftime("%F %T");
        msg=length($0)?$0:" ";
        printf "%s | %s | %s | 1\n", t, n, msg >> f; fflush(f);
    }'
)

# Fehler- und Exit-Traps
trap 'logging "ERROR at line ${LINENO:-?}: ${BASH_COMMAND:-?}" "$?"' ERR
trap 'rc=$?; logging "EXIT" "$rc"; exit "$rc"' EXIT
