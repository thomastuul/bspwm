#!/usr/bin/env python3
"""Exercise microphone selection against isolated PulseAudio/PipeWire fixtures."""

import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
INTERNAL = {
    "name": "alsa_input.another_computer.analog-stereo",
    "properties": {"device.form_factor": "internal"},
    "ports": [{"name": "analog-input-internal-mic", "availability": "availability unknown"}],
    "active_port": "analog-input-internal-mic",
}
EFFECTS = {"name": "easyeffects_source", "mute": False, "properties": {}}


def node(identifier, name):
    return {"id": identifier, "type": "PipeWire:Interface:Node", "info": {"props": {"node.name": name}}}


def link(output, input_, state="paused"):
    return {"type": "PipeWire:Interface:Link", "info": {"output-node-id": output, "input-node-id": input_, "state": state}}


class AudioSelectionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        for command in ("pactl", "pw-dump"):
            executable = self.path / command
            executable.write_text(
                "#!/usr/bin/python3\n"
                "import json, os, pathlib, sys\n"
                "path = pathlib.Path(os.environ['PULSE_FIXTURE'])\n"
                "sources = json.loads(path.read_text())\n"
                "if pathlib.Path(sys.argv[0]).name == 'pw-dump':\n"
                "    print(pathlib.Path(os.environ['GRAPH_FIXTURE']).read_text())\n"
                "elif sys.argv[1:] == ['list', 'short', 'sources']:\n"
                "    for index, source in enumerate(sources):\n"
                "        print(index, source['name'], 'PipeWire', sep='\\t')\n"
                "elif sys.argv[1:] == ['--format=json', 'list', 'sources']:\n"
                "    print(json.dumps(sources))\n"
                "elif sys.argv[1] == 'set-source-port':\n"
                "    for source in sources:\n"
                "        if source['name'] == sys.argv[2]:\n"
                "            source['active_port'] = sys.argv[3]\n"
                "    path.write_text(json.dumps(sources))\n"
                "else:\n"
                "    sys.exit(1)\n"
            )
            executable.chmod(0o700)
        self.env = dict(os.environ, PATH=f"{self.path}:{os.environ['PATH']}")
        self.env.pop("SCREENCAST_AUDIO", None)
        self.env["PULSE_FIXTURE"] = str(self.path / "sources.json")
        self.env["GRAPH_FIXTURE"] = str(self.path / "graph.json")
        # Never access the host microphone when testing a disconnected route.
        probe = self.path / "parec"
        probe.write_text("#!/bin/sh\nexit 1\n")
        probe.chmod(0o700)
        self.fixtures([INTERNAL])

    def fixtures(self, sources, graph=()):
        Path(self.env["PULSE_FIXTURE"]).write_text(json.dumps(sources))
        Path(self.env["GRAPH_FIXTURE"]).write_text(json.dumps(graph))

    def run_shell(self, script):
        return subprocess.run(
            ["bash", "-euc", 'source "$1/lib/screencast-audio.sh"\n' + script, "test", str(ROOT)],
            env=self.env, capture_output=True, text=True, check=True, timeout=5,
        ).stdout.splitlines()

    def select(self):
        return self.run_shell(
            'screencast_select_audio\nprintf "%s\\n" "$source_name" "$audio_label" '
            '"$audio_physical_source" "$audio_port" "$audio_previous_port"'
        )

    def graph(self, source=None):
        return [node(1, source or INTERNAL["name"]), node(2, "ee_sie_speex"),
                node(3, "easyeffects_source"), link(1, 2), link(2, 3)]

    def test_internal_on_arbitrary_computer(self):
        result = self.select()
        self.assertEqual(result[0], INTERNAL["name"])
        self.assertIn("ohne EasyEffects", result[1])

    def test_usb_priority(self):
        self.fixtures([INTERNAL, {"name": "alsa_input.Poly_Studio_P5"}, {"name": "alsa_input.FIFINE"}])
        self.assertEqual(self.select()[0], "alsa_input.FIFINE")

    def test_poly_priority(self):
        self.fixtures([INTERNAL, {"name": "alsa_input.Poly_Studio_P5"}])
        self.assertEqual(self.select()[0], "alsa_input.Poly_Studio_P5")

    def test_monitors_and_line_inputs_are_excluded(self):
        line = dict(INTERNAL, ports=[{"name": "analog-input-linein"}], active_port="analog-input-linein")
        self.fixtures([dict(INTERNAL, name="FIFINE.monitor"), line])
        self.assertEqual(self.select()[0], "")

    def test_internal_port_does_not_require_form_factor(self):
        self.fixtures([dict(INTERNAL, properties={})])
        self.assertEqual(self.select()[0], INTERNAL["name"])

    def test_digital_internal_microphone_without_ports(self):
        self.fixtures([dict(INTERNAL, name="alsa_input.digital-mic", ports=[], active_port=None)])
        self.assertEqual(self.select()[0], "alsa_input.digital-mic")

    def test_unavailable_internal_port_is_not_selected(self):
        source = copy.deepcopy(INTERNAL)
        source["ports"][0]["availability"] = "not available"
        self.fixtures([source])
        self.assertEqual(self.select()[0], "")

    def test_effects_require_connected_microphone(self):
        self.fixtures([INTERNAL, EFFECTS], self.graph())
        self.assertEqual(self.select()[0], "easyeffects_source")

    def test_effects_on_different_microphone_are_ignored(self):
        self.fixtures([INTERNAL, EFFECTS], self.graph("alsa_input.some_usb_mic"))
        self.assertEqual(self.select()[0], INTERNAL["name"])

    def test_unconnected_or_muted_effects_are_ignored(self):
        for effects, graph in [(EFFECTS, []), (dict(EFFECTS, mute=True), self.graph()),
                               (EFFECTS, [*self.graph()[:-1], link(2, 3, "error")])]:
            with self.subTest(effects=effects, graph=graph):
                self.fixtures([INTERNAL, effects], graph)
                self.assertEqual(self.select()[0], INTERNAL["name"])

    def test_graph_cycle_terminates(self):
        self.fixtures([INTERNAL, EFFECTS], [*self.graph(), link(2, 1)])
        self.assertEqual(self.select()[0], "easyeffects_source")

    def test_idle_effects_source_is_woken(self):
        self.fixtures([INTERNAL, EFFECTS])
        self.env["WAKE_GRAPH"] = json.dumps(self.graph())
        (self.path / "parec").write_text(
            "#!/usr/bin/python3\n"
            "import os, pathlib, time\n"
            "pathlib.Path(os.environ['GRAPH_FIXTURE']).write_text(os.environ['WAKE_GRAPH'])\n"
            "time.sleep(3)\n"
        )
        self.assertEqual(self.select()[0], "easyeffects_source")

    def test_no_devices(self):
        self.fixtures([])
        self.assertEqual(self.select()[0], "")

    def test_explicit_silent_mode(self):
        self.env["SCREENCAST_AUDIO"] = "none"
        self.assertEqual(self.select()[0], "")

    def test_missing_jq_preserves_usb_selection(self):
        self.fixtures([INTERNAL, {"name": "alsa_input.FIFINE"}])
        result = self.run_shell(
            'command() { [[ $* != "-v jq" ]] && builtin command "$@"; }\n'
            'screencast_select_audio\nprintf "%s\\n" "$source_name"'
        )
        self.assertEqual(result, ["alsa_input.FIFINE"])

    def test_missing_pipewire_tools_uses_direct_internal_microphone(self):
        self.fixtures([INTERNAL, EFFECTS], self.graph())
        result = self.run_shell(
            'command() { [[ $* != "-v pw-dump" ]] && builtin command "$@"; }\n'
            'screencast_select_audio\nprintf "%s\\n" "$source_name"'
        )
        self.assertEqual(result, [INTERNAL["name"]])

    def test_headset_port_is_remembered_for_restore(self):
        self.fixtures([dict(INTERNAL, active_port="analog-input-headset-mic"), EFFECTS], self.graph())
        result = self.select()
        self.assertEqual(result[0], "easyeffects_source")
        self.assertEqual(result[2:], [INTERNAL["name"], "analog-input-internal-mic", "analog-input-headset-mic"])

    def test_failed_recording_restores_previous_input_port(self):
        self.fixtures([dict(INTERNAL, active_port="analog-input-headset-mic")])
        for command, script in {
            "ffmpeg": "exit 1",
            "xdpyinfo": "printf '  dimensions:  640x480 pixels\\n'",
            "notify-send": "exit 0",
        }.items():
            executable = self.path / command
            executable.write_text("#!/bin/sh\n" + script + "\n")
            executable.chmod(0o700)
        runtime = self.path / "runtime"
        runtime.mkdir()
        self.env.update(HOME=str(self.path), XDG_RUNTIME_DIR=str(runtime))
        result = subprocess.run(
            ["bash", str(ROOT / "bin/screencast.sh")], env=self.env,
            capture_output=True, text=True, timeout=5,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("Aufnahme konnte nicht gestartet werden", result.stderr)
        self.assertFalse((runtime / "screencast.pid").exists())
        self.assertFalse((runtime / "screencast.port").exists())
        source = json.loads(Path(self.env["PULSE_FIXTURE"]).read_text())[0]
        self.assertEqual(source["active_port"], "analog-input-headset-mic")

    def test_port_restore_preserves_manual_changes_and_disconnection(self):
        for current in ["analog-input-internal-mic", "analog-input-linein", None]:
            with self.subTest(current=current):
                sources = [dict(INTERNAL, active_port=current)] if current else []
                self.fixtures(sources)
                state = self.path / "screencast.port"
                state.write_text(INTERNAL["name"] + "\nanalog-input-headset-mic\nanalog-input-internal-mic\n")
                self.env["PORT_STATE"] = str(state)
                self.run_shell('screencast_restore_audio_port "$PORT_STATE"')
                self.assertFalse(state.exists())
                actual = json.loads(Path(self.env["PULSE_FIXTURE"]).read_text())
                if current:
                    expected = "analog-input-headset-mic" if current == "analog-input-internal-mic" else current
                    self.assertEqual(actual[0]["active_port"], expected)


if __name__ == "__main__":
    unittest.main()
