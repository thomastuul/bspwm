#!/usr/bin/env python3
"""Exercise monitor profiles with the installed panel on an isolated Xvfb."""
import ctypes
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(sys.argv[1]).resolve()
WATCHER = Path(sys.argv[2]).resolve()


def wait_for(predicate):
    for _ in range(100):
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError("timed out")


with tempfile.TemporaryDirectory(prefix="sliverbar-profile-") as directory:
    tmp = Path(directory)
    config = tmp / "config"
    repo = config / "bspwm"
    repo.mkdir(parents=True)
    for part in ("lib", "hosts", "bin"):
        shutil.copytree(ROOT / part, repo / part)
    runtime = tmp / "runtime"
    runtime.mkdir(mode=0o700)
    (tmp / ".local/bin").mkdir(parents=True)
    (tmp / ".local/bin/sliverbar").symlink_to(BINARY)
    mocks = tmp / "mocks"
    mocks.mkdir()

    def executable(name, body):
        path = mocks / name
        path.write_text("#!/bin/bash\nset -eu\n" + body)
        path.chmod(0o755)

    executable("bspc", 'if (($# == 2)); then cat "$TEST_PADDING"; else printf "%s" "$3" >"$TEST_PADDING"; fi\n')
    executable("autorandr", '''
if [[ $* == *--load* ]]; then echo 'Config already loaded'; exit 0; fi
printf '%s\n' "$TEST_PROFILE"
''')
    executable("xdo", 'printf "%s\\n" "$*" >>"$TEST_HIDDEN"\n')
    padding = tmp / "padding"
    padding.write_text("30")
    base = config / "sliverbar/panel.conf"
    base.parent.mkdir()
    base.write_text("font=Monospace:style=Regular:size=15\n"
                    "icon_font=Monospace:style=Regular:size=15\nheight=30\n"
                    "workspace_backend=none\nagenda_provider=none\n"
                    "block_padding=9\ncolor_panel_bg=#191A21\n" +
                    "".join(f"module_{module}=disabled\n" for module in
                            ("clock", "title", "cpu", "battery", "screencast", "volume",
                             "network", "brightness", "weather", "launcher", "tray",
                             "power", "inhibitor", "timer")))
    original = base.read_bytes()
    xvfb = subprocess.Popen(["Xvfb", "-displayfd", "1", "-screen", "0", "1280x720x24"],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    display = ":" + xvfb.stdout.readline().strip()
    env = dict(os.environ, HOME=str(tmp), XDG_CONFIG_HOME=str(config),
               XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(tmp / "state"),
               BSPWM_HOST_OVERRIDE="Pegasus4", DISPLAY=display,
               PATH=f"{mocks}:{os.environ['PATH']}", TEST_PADDING=str(padding),
               TEST_HIDDEN=str(tmp / "hidden"), TEST_PROFILE="ioc-27m2u-4k")
    for key in ("AUTORANDR_CURRENT_PROFILE", "SLIVERBAR_CONFIG", "BSPWM_HOST_PROFILE_LOADED"):
        env.pop(key, None)
    generated = runtime / "bspwm" / ("sliverbar-" + re.sub(r"[^a-zA-Z0-9_.-]", "_", display)) / "panel.conf"
    stamp = generated.with_name("applied")
    helper = repo / "bin/sliverbar-refresh.sh"
    xlib = ctypes.CDLL("libX11.so.6")
    xlib.XOpenDisplay.argtypes = [ctypes.c_char_p]
    xlib.XOpenDisplay.restype = ctypes.c_void_p
    connection = xlib.XOpenDisplay(display.encode())
    assert connection
    xlib.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
    xlib.XDefaultRootWindow.restype = ctypes.c_ulong
    xlib.XQueryTree.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_void_p,
                               ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
    xlib.XFetchName.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_void_p]
    xlib.XGetGeometry.argtypes = [ctypes.c_void_p, ctypes.c_ulong] + [ctypes.c_void_p] * 7
    xlib.XFree.argtypes = [ctypes.c_void_p]

    def panel_height():
        root, parent = ctypes.c_ulong(), ctypes.c_ulong()
        children = ctypes.POINTER(ctypes.c_ulong)()
        count = ctypes.c_uint()
        xlib.XQueryTree(connection, xlib.XDefaultRootWindow(connection), ctypes.byref(root),
                       ctypes.byref(parent), ctypes.byref(children), ctypes.byref(count))
        height = None
        for i in range(count.value):
            name = ctypes.c_char_p()
            xlib.XFetchName(connection, children[i], ctypes.byref(name))
            if name.value == b"sliverbar":
                x, y = ctypes.c_int(), ctypes.c_int()
                width, h, border, depth = (ctypes.c_uint() for _ in range(4))
                xlib.XGetGeometry(connection, children[i], ctypes.byref(root), ctypes.byref(x),
                                 ctypes.byref(y), ctypes.byref(width), ctypes.byref(h),
                                 ctypes.byref(border), ctypes.byref(depth))
                height = h.value
            if name:
                xlib.XFree(name)
        xlib.XFree(children)
        return height

    def run(profile=None, success=True):
        current = dict(env)
        if profile is not None:
            current["AUTORANDR_CURRENT_PROFILE"] = profile
        result = subprocess.run([str(helper)], env=current, text=True, capture_output=True, timeout=20)
        assert (result.returncode == 0) == success, (result.stdout, result.stderr)
        return result

    def check(height, font):
        content = generated.read_text()
        assert f"height={height}\n" in content
        assert content.count(f":size={font}\n") == 2
        assert "block_padding=9\ncolor_panel_bg=#191A21\n" in content
        assert padding.read_text() == str(height)
        wait_for(lambda: panel_height() == height)
        return stamp.read_text().split()[0]

    try:
        run()  # Startup detects the monitor even without an autorandr hook.
        first = check(40, 17)
        run("ioc-27m2u-4k")
        assert check(40, 17) == first
        workers = [subprocess.Popen([str(helper)], env=env, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, text=True) for _ in range(4)]
        for worker in workers:
            _, stderr = worker.communicate(timeout=20)
            assert worker.returncode == 0, stderr
        assert check(40, 17) == first
        run("lg-hdr-wqhd")
        second = check(30, 15)
        assert second != first
        run("unknown")
        assert check(30, 15) == second
        run("ioc-27m2u-4k")
        third = check(40, 17)
        assert third != second
        assert base.read_bytes() == original
        # Reject bad input before interrupting a working panel.
        base.write_text(base.read_text() + "invalid_setting=1\n")
        run("lg-hdr-wqhd", success=False)
        assert check(40, 17) == third
        base.write_bytes(original)
        # Hidden panels stay hidden, including a size-changing refresh.
        padding.write_text("0")
        run("lg-hdr-wqhd")
        assert padding.read_text() == "0"
        assert (tmp / "hidden").read_text().strip() == "hide -a sliverbar"
        wait_for(lambda: panel_height() == 30)
        padding.write_text("30")
        # Execute the real watcher apply function on the already-loaded path.
        watcher_library = tmp / "watcher.sh"
        watcher_library.write_text(WATCHER.read_text().removesuffix('main "$@"\n'))
        result = subprocess.run(["bash", "-c", 'source "$1"; apply_layout true', "bash",
                                 str(watcher_library)], env=env, text=True, capture_output=True, timeout=20)
        assert result.returncode == 0, result.stderr
        assert "Config already loaded" in result.stdout
        check(40, 17)
        # Other hosts must not change either generated config or processes.
        before = stamp.read_bytes()
        subprocess.run([str(helper)], env=dict(env, BSPWM_HOST_OVERRIDE="Ikarus2"), check=True)
        assert stamp.read_bytes() == before
        print("PASS: startup detection, 4K/LG/fallback, actual X11 heights, fonts, padding, "
              "idempotence, concurrency, invalid config, hidden panel, already-loaded watcher, host isolation")
    finally:
        if stamp.exists():
            try:
                os.kill(int(stamp.read_text().split()[0]), signal.SIGTERM)
            except ProcessLookupError:
                pass
        xvfb.terminate()
        xvfb.wait(timeout=5)
