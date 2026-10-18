#!/usr/bin/env python3
"""Verify host timings through the actual autostart idle command block."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "autostart").read_text()
block = source.split("xset +dpms", 1)[1].split("start_if_executable", 1)[0]
block = "xset +dpms" + block

with tempfile.TemporaryDirectory(prefix="bspwm-idle-test-") as directory:
    dimmer = Path(directory) / "dimmer"
    dimmer.touch(mode=0o700)
    for host in ("Ikarus2", "IKARUS2", "Pegasus4", "unknown-host"):
        old = host.lower() == "ikarus2"
        for override in (None, "4321"):
            env = dict(HOME=os.environ["HOME"], PATH=os.environ["PATH"],
                       BSPWM_CONFIG_DIR=str(ROOT), BSPWM_HOST_OVERRIDE=host,
                       XSECURELOCK_DIMMER=str(dimmer))
            if override is not None:
                env["XSECURELOCK_DIM_TIME_MS"] = override
            script = '''
set -euo pipefail
source "$BSPWM_CONFIG_DIR/lib/host-profile.sh"
xset() { printf 'xset %s\\n' "$*"; }
xss-lock() { :; }
xsecurelock() { :; }
start_once() { printf 'start %s dim=%s\\n' "$*" "$XSECURELOCK_DIM_TIME_MS"; }
start_if_available() { printf 'start %s\\n' "$*"; }
log() { printf 'unexpected log: %s\\n' "$*"; exit 1; }
'''
            result = subprocess.run(["bash", "-c", script + block], env=env,
                                    check=True, text=True, capture_output=True)
            dim = override or ("10000" if old else "15000")
            expected = [
                "xset +dpms",
                "xset s 300 10" if old else "xset s 600 15",
                "xset dpms 400 600 900" if old else "xset dpms 1200 1500 2400",
                f"start xss-lock -n {dimmer} --transfer-sleep-lock -- xsecurelock dim={dim}",
                "start xautolock -time " + ("30" if old else "60")
                + " -detectsleep -locker systemctl suspend-then-hibernate",
            ]
            assert result.stdout.splitlines() == expected, (host, override, result.stdout)
print("Idle timings: Ikarus2, case normalization, Pegasus4, unknown host and dimmer overrides passed")
