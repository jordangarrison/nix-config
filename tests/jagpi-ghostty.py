#!/usr/bin/env python3
"""Exercise the launcher with fake niri/Ghostty; never touch the live desktop."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = (
    Path(sys.argv.pop(1)) if len(sys.argv) > 1 else
    Path(__file__).resolve().parents[1] / "modules/home/wlr-which-key/jagpi-ghostty.sh"
)
APP_ID = "dev.jordangarrison.jagpi"
FAKE = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import time

root = Path(os.environ["XDG_RUNTIME_DIR"])
args = sys.argv[1:]
if Path(sys.argv[0]).name == "ghostty":
    with (root / "launches").open("a") as out:
        out.write(json.dumps(args) + "\n")
    if os.environ.get("FAIL_START"):
        sys.exit(1)
    # Simulate the gap between process creation and niri seeing the window.
    time.sleep(0.2)
    window = [{"id": 42, "app_id": "dev.jordangarrison.jagpi", "title": "Jagpi"}]
    (root / "new-windows.json").write_text(json.dumps(window))
    (root / "new-windows.json").replace(root / "windows.json")
elif args == ["msg", "--json", "windows"]:
    if os.environ.get("FAIL_IPC"):
        sys.exit(1)
    if os.environ.get("MALFORMED_IPC"):
        print("not json")
    else:
        print((root / "windows.json").read_text())
elif args[:4] == ["msg", "action", "focus-window", "--id"]:
    with (root / "focuses").open("a") as out:
        out.write(args[4] + "\n")
    if os.environ.get("FAIL_FOCUS"):
        sys.exit(1)
else:
    sys.exit(2)
'''


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        binary = self.root / "bin"
        binary.mkdir()
        for name in ("niri", "ghostty"):
            fake = binary / name
            fake.write_text(FAKE.replace("#!/usr/bin/env python3", f"#!{sys.executable}", 1))
            fake.chmod(0o755)
        self.env = os.environ | {
            "PATH": f"{binary}:{os.environ['PATH']}",
            "XDG_RUNTIME_DIR": str(self.root),
        }
        self.windows([])

    def windows(self, windows):
        (self.root / "windows.json").write_text(json.dumps(windows))

    def run_launcher(self, *command, **env):
        return subprocess.run(
            ["bash", "-euo", "pipefail", str(SCRIPT), *(command or ("jagpi",))],
            env=self.env | env, capture_output=True, text=True, timeout=15,
        )

    def lines(self, name):
        path = self.root / name
        return path.read_text().splitlines() if path.exists() else []

    def launches(self):
        return [json.loads(line) for line in self.lines("launches")]

    def test_existing_window_focused_by_app_id_not_title(self):
        self.windows([
            {"id": 1, "app_id": "com.mitchellh.ghostty", "title": "Jagpi"},
            {"id": 17, "app_id": APP_ID, "title": "main/29514"},
        ])
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.lines("focuses"), ["17"])
        self.assertEqual(self.launches(), [])

    def test_closed_window_starts_once_and_repeated_press_reuses_it(self):
        for _ in range(2):
            result = self.run_launcher()
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.launches(), [[
            f"--class={APP_ID}", "--gtk-single-instance=false",
            "--title=Jagpi", "-e", "jagpi",
        ]])
        self.assertEqual(self.lines("focuses"), ["42", "42"])

    def test_remote_command_preserves_argument_boundaries(self):
        result = self.run_launcher("ssh", "-t", "endeavour", "jagpi")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.launches()[0][-5:], ["-e", "ssh", "-t", "endeavour", "jagpi"])

    def test_concurrent_presses_start_only_one_window(self):
        processes = [subprocess.Popen(
            ["bash", "-euo", "pipefail", str(SCRIPT), "jagpi"], env=self.env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        ) for _ in range(4)]
        for process in processes:
            _, stderr = process.communicate(timeout=15)
            self.assertEqual(process.returncode, 0, stderr)
        self.assertEqual(len(self.launches()), 1)
        self.assertEqual(self.lines("focuses"), ["42"] * 4)

    def test_ipc_failure_does_not_launch(self):
        result = self.run_launcher(FAIL_IPC="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.launches(), [])

    def test_malformed_ipc_does_not_launch(self):
        result = self.run_launcher(MALFORMED_IPC="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.launches(), [])

    def test_focus_failure_does_not_duplicate_window(self):
        self.windows([{"id": 17, "app_id": APP_ID}])
        result = self.run_launcher(FAIL_FOCUS="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.launches(), [])

    def test_failed_start_is_reported(self):
        result = self.run_launcher(FAIL_START="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("did not become ready", result.stderr)
        self.assertIn("jagpi-ghostty.log", result.stderr)
        self.assertEqual(len(self.launches()), 1)

    def test_missing_runtime_directory_does_not_launch(self):
        result = self.run_launcher(XDG_RUNTIME_DIR="")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.launches(), [])


if __name__ == "__main__":
    unittest.main()
