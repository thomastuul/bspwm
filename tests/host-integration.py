#!/usr/bin/env python3
"""Exercise host integration in an isolated X server and temporary config home."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def run(*args, env, **kwargs):
    return subprocess.run(args, env=env, check=True, text=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15, **kwargs)


def wait_for(predicate):
    for _ in range(100):
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError("timed out")


with tempfile.TemporaryDirectory(prefix="bspwm-integration-") as temporary:
    tmp = Path(temporary)
    config = tmp / "config"
    repo = config / "bspwm"
    repo.mkdir(parents=True)
    for directory in ("lib", "hosts", "bin"):
        shutil.copytree(ROOT / directory, repo / directory)
    runtime = tmp / "runtime"
    runtime.mkdir(mode=0o700)
    mocks = tmp / "mocks"
    mocks.mkdir()
    env = dict(os.environ, XDG_CONFIG_HOME=str(config), XDG_RUNTIME_DIR=str(runtime),
               BSPWM_HOST_OVERRIDE="Ikarus2", PATH=f"{mocks}:{os.environ['PATH']}")
    env.pop("BSPWM_HOST_PROFILE_LOADED", None)
    env.pop("BSPWM_CONFIG_DIR", None)
    xvfb = subprocess.Popen(["Xvfb", "-displayfd", "1", "-screen", "0", "1920x1080x24"],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    env["DISPLAY"] = ":" + xvfb.stdout.readline().strip()
    conky_config = runtime / f"conky-{os.getuid()}.conf"
    processes = []

    def managed_pids():
        result = subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", "conky"],
                                text=True, capture_output=True)
        matches = []
        for pid in result.stdout.split():
            try:
                argv = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
                if f"--config={conky_config}".encode() in argv:
                    matches.append(int(pid))
            except FileNotFoundError:
                pass
        return matches

    def executable(name, text):
        path = mocks / name
        path.write_text("#!/bin/bash\nset -eu\n" + text)
        path.chmod(0o755)
        return path

    generator = executable("generator", '''
[[ $CONKY_GENERATE_ONLY == 1 ]]
cat >"$XDG_RUNTIME_DIR/conky-$UID.conf" <<CONFIG
conky.config = {out_to_x=true, own_window=true, background=false,
 alignment='bottom_left', minimum_width=300, maximum_width=300,
 gap_x=10, gap_y=10, update_interval=0.1};
conky.text = [[geometry test]]
CONFIG
''')
    generator_source = generator.read_text()
    env["CONKY_START"] = str(generator)
    helper = repo / "bin/conky-refresh.sh"
    try:
        # Real Conky on Xvfb verifies start, adoption, reload and concurrency.
        unrelated_config = tmp / "unrelated.conf"
        unrelated_config.write_text("conky.config={out_to_x=false,out_to_console=false,update_interval=1};conky.text=[[other]]")
        unrelated = subprocess.Popen(["conky", f"--config={unrelated_config}"], env=env,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        processes.append(unrelated)
        run(str(helper), env=env)
        wait_for(lambda: len(managed_pids()) == 1)
        original_pid = managed_pids()[0]
        assert "xinerama_head = 0" in conky_config.read_text()
        # Force a changed config, then race callers: all must reuse the same PID.
        generator.write_text(generator.read_text().replace("geometry test", "updated geometry"))
        workers = [subprocess.Popen([str(helper)], env=env, stdout=subprocess.DEVNULL,
                                    stderr=subprocess.PIPE, text=True) for _ in range(5)]
        for worker in workers:
            _, stderr = worker.communicate(timeout=15)
            assert worker.returncode == 0, stderr
        assert managed_pids() == [original_pid]
        assert "updated geometry" in conky_config.read_text()
        assert unrelated.poll() is None
        previous = conky_config.read_bytes()
        generator.write_text("#!/bin/bash\nexit 1\n")
        assert subprocess.run([str(helper)], env=env, capture_output=True).returncode != 0
        assert conky_config.read_bytes() == previous
        with (repo / "hosts/Ikarus2/profile.sh").open("a") as stream:
            stream.write("\nBSPWM_ENABLE_CONKY=0\nBSPWM_TOP_PADDING=41\n")
        run(str(helper), env=env)
        assert managed_pids() == [original_pid]
        assert conky_config.read_bytes() == previous
        print("Conky: start, scoped reload, concurrent calls, generator failure and disabled feature passed")

        # Test the actual sxhkd parser and key binding with fake panel commands.
        state = tmp / "padding"
        state.write_text("0")
        env["TEST_PADDING"] = str(state)
        executable("bspc", 'if (($# == 2)); then cat "$TEST_PADDING"; else printf "%s" "$3" >"$TEST_PADDING"; fi\n')
        executable("xdo", "exit 0\n")
        binding = (ROOT / "sxhkd/sxhkdrc").read_text().split("super + b\n", 1)[1].split("\n\n", 1)[0]
        rc = tmp / "sxhkdrc"
        rc.write_text("super + b\n" + binding + "\n")
        sxhkd = subprocess.Popen(["sxhkd", "-c", str(rc)], env=env,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        processes.append(sxhkd)
        time.sleep(0.3)
        run("xdotool", "key", "super+b", env=env)
        wait_for(lambda: state.read_text() == "41")
        run("xdotool", "key", "super+b", env=env)
        wait_for(lambda: state.read_text() == "0")
        assert sxhkd.poll() is None
        print("sxhkd on Xvfb: show uses padding 41; hide uses 0")

        # The shared hook must not apply laptop desktop operations on Pegasus4.
        executable("bspc", 'printf "%s\\n" "$*" >>"$TEST_PADDING"; exit 0\n')
        executable("xrandr", "exit 0\n")
        with (repo / "hosts/Pegasus4/profile.sh").open("a") as stream:
            stream.write("\nBSPWM_ENABLE_CONKY=0\nBSPWM_ENABLE_SLIVERBAR=0\n")
        env["XDG_STATE_HOME"] = str(tmp / "state")
        state.write_text("")
        run(str(repo / "bin/autorandr-postswitch.sh"), "dock-open",
            env=dict(env, BSPWM_HOST_OVERRIDE="Pegasus4"))
        assert state.read_text().splitlines() == ["query -M --names"]
        state.write_text("")
        run(str(repo / "bin/autorandr-postswitch.sh"), "dock-open", env=env)
        assert state.read_text().splitlines() == ["query -M --names"] * 3
        print("autorandr: laptop normalization is gated by the explicit host output pair")

        # Simulate a primary output offset to the right of a different head.
        for pid in managed_pids():
            os.kill(pid, 15)
        wait_for(lambda: not managed_pids())
        with (repo / "hosts/Ikarus2/profile.sh").open("a") as stream:
            stream.write("\nBSPWM_ENABLE_CONKY=1\n")
        generator.write_text(generator_source)
        executable("conky", "exit 0\n")
        executable("xrandr", "printf '%s\\n' 'HDMI-1 connected 3840x1600+0+0' 'eDP-1 connected primary 1920x1080+3840+200'\n")
        executable("xdpyinfo", "printf '%s\\n' '  head #0: 3840x1600 @ 0,0' '  head #1: 1920x1080 @ 3840,200'\n")
        run(str(helper), env=env)
        assert "xinerama_head = 1" in conky_config.read_text()
        assert "1920x1080+3840+200" in conky_config.read_text()
        previous = conky_config.read_bytes()
        executable("xrandr", "printf '%s\\n' 'eDP-1 connected primary 1920x1080-1920+0'\n")
        assert subprocess.run([str(helper)], env=env, capture_output=True).returncode != 0
        assert conky_config.read_bytes() == previous
        print("Conky topology fixtures: primary selection, nonzero offsets and unsupported geometry passed")
    finally:
        for pid in managed_pids():
            try:
                os.kill(pid, 15)
            except ProcessLookupError:
                pass
        for process in reversed(processes):
            process.terminate()
            process.wait(timeout=5)
        xvfb.terminate()
        xvfb.wait(timeout=5)
