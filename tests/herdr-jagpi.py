#!/usr/bin/env python3
"""Test the launcher against a fake Herdr; never connect to the live app."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "modules/home/wlr-which-key/herdr-jagpi.sh"
FAKE = r'''#!/usr/bin/env bash
set -euo pipefail
home="${HERDR_APP_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr-app}"
case "${1:-}" in
  status)
    if [[ -f "$home/ready" ]]; then exit 0; fi
    if [[ -f "$home/started" && "${NEVER_READY:-}" != 1 ]]; then
      count=$(cat "$home/count" 2>/dev/null || echo 0)
      echo "$((count + 1))" > "$home/count"
      if (( count >= 2 )); then touch "$home/ready"; exit 0; fi
    fi
    exit 1 ;;
  do)
    [[ "$*" == 'do layout.switch --name jagpi' ]]
    echo switch >> "$home/calls"
    [[ "${FAIL_SWITCH:-}" != 1 ]] ;;
  '')
    if [[ -f "$home/ready" ]]; then
      echo raise >> "$home/calls"
    else
      echo launch >> "$home/calls"
      touch "$home/started"
    fi ;;
  *) exit 2 ;;
esac
'''


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.home = root / "app home"
        (self.home / "layouts").mkdir(parents=True)
        (self.home / "layouts/jagpi.json").write_text("{}")
        binary = root / "bin"
        binary.mkdir()
        fake = binary / "herdr-app"
        fake.write_text(FAKE)
        fake.chmod(0o755)
        self.env = os.environ | {
            "PATH": f"{binary}:{os.environ['PATH']}",
            "HERDR_APP_HOME": str(self.home),
        }

    def run_launcher(self, **env):
        return subprocess.run(
            ["bash", "-euo", "pipefail", str(SCRIPT)],
            env=self.env | env, capture_output=True, text=True, timeout=25,
        )

    def calls(self):
        path = self.home / "calls"
        return path.read_text().splitlines() if path.exists() else []

    def test_existing_window_switches_then_raises_without_launch(self):
        (self.home / "ready").touch()
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["switch", "raise"])

    def test_closed_window_starts_once_and_repeated_press_reuses_it(self):
        for _ in range(2):
            result = self.run_launcher()
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["launch", "switch", "raise", "switch", "raise"])

    def test_concurrent_presses_start_only_one_window(self):
        processes = [subprocess.Popen(
            ["bash", "-euo", "pipefail", str(SCRIPT)], env=self.env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        ) for _ in range(4)]
        for process in processes:
            _, stderr = process.communicate(timeout=25)
            self.assertEqual(process.returncode, 0, stderr)
        self.assertEqual(self.calls().count("launch"), 1)
        self.assertEqual(self.calls().count("switch"), 4)
        self.assertEqual(self.calls().count("raise"), 4)

    def test_missing_layout_does_not_launch_or_switch(self):
        (self.home / "layouts/jagpi.json").unlink()
        result = self.run_launcher()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("layout not found", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_failed_switch_does_not_raise_wrong_layout(self):
        (self.home / "ready").touch()
        result = self.run_launcher(FAIL_SWITCH="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), ["switch"])

    def test_failed_start_is_bounded(self):
        result = self.run_launcher(NEVER_READY="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("did not become ready", result.stderr)
        self.assertEqual(self.calls(), ["launch"])

    def test_xdg_config_home(self):
        # Keep the same fake app home while exercising XDG_CONFIG_HOME.
        target = self.home.parent / "herdr-app"
        self.home.rename(target)
        self.home = target
        (self.home / "ready").touch()
        result = self.run_launcher(HERDR_APP_HOME="", XDG_CONFIG_HOME=str(target.parent))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["switch", "raise"])


if __name__ == "__main__":
    unittest.main()
