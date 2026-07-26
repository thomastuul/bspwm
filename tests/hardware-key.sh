#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)

cleanup() {
    rm -rf -- "$test_root"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$test_root/bin" "$test_root/home"

cat >"$test_root/bin/sliverbar" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$HARDWARE_KEY_SLIVERBAR_LOG"
EOF

cat >"$test_root/bin/wpctl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$HARDWARE_KEY_WPCTL_LOG"
EOF

chmod +x "$test_root/bin/sliverbar" "$test_root/bin/wpctl"
export PATH="$test_root/bin:/usr/bin:/bin"
export HOME="$test_root/home"
export HARDWARE_KEY_SLIVERBAR_LOG="$test_root/sliverbar.log"
export HARDWARE_KEY_WPCTL_LOG="$test_root/wpctl.log"

"$repository_root/bin/hardware-key.sh" volume-mute

grep -Fx -- '--action volume toggle' "$HARDWARE_KEY_SLIVERBAR_LOG"
[[ ! -e $HARDWARE_KEY_WPCTL_LOG ]]

printf 'hardware key tests passed\n'
