"""Run with python3 -m unittest discover -s ci/claude-statusline."""

import json
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest

WRAPPER = (Path(__file__).resolve().parents[2] /
           "users/jordangarrison/agents/claude/jagpi-statusline.py")
PAYLOAD = b'''{
    "workspace":{"current_dir":"/not-published"},"session_id":"not-published",
    "rate_limits":{"five_hour":{"used_percentage":0,"resets_at":1800000000,
    "extra":"not-published"},"seven_day":{"used_percentage":true,"resets_at":1800000000},
    "spend_limit":{"used_percentage":33,"resets_at":1800000000}}
}\n\n'''


class StatuslineFeedTest(unittest.TestCase):
    def setUp(self):
        home = tempfile.TemporaryDirectory()
        self.addCleanup(home.cleanup)
        self.home = Path(home.name)
        self.state = self.home / "state"
        self.env = {"HOME": str(self.home), "XDG_STATE_HOME": str(self.state)}
        self.dest = self.state / "jagpi/test-instance/claude-statusline.json"

    def render(self, payload=PAYLOAD, code=0):
        result = subprocess.run(
            [sys.executable, WRAPPER, "test-instance", sys.executable, "-c",
             f"import sys; sys.stdout.buffer.write(sys.stdin.buffer.read()); sys.exit({code})"],
            env=self.env, input=payload, capture_output=True, check=False,
        )
        self.assertEqual(result.returncode, code)
        self.assertEqual(result.stdout, payload)
        self.assertEqual(result.stderr, b"")

    def test_preserves_stdin_and_publishes_only_private_valid_windows(self):
        self.render(code=17)
        self.assertEqual(stat.S_IMODE(self.dest.stat().st_mode), 0o600)
        self.assertEqual(json.loads(self.dest.read_bytes()), {"rate_limits": {
            "five_hour": {"used_percentage": 0, "resets_at": 1800000000},
        }})
        inode = self.dest.stat().st_ino
        self.render(PAYLOAD.replace(b'"used_percentage":0', b'"used_percentage":50'))
        self.assertNotEqual(self.dest.stat().st_ino, inode)
        self.assertEqual(list(self.dest.parent.iterdir()), [self.dest])
        self.assertEqual(json.loads(self.dest.read_bytes())["rate_limits"]["five_hour"]["used_percentage"], 50)

    def test_does_not_replace_good_sample_on_invalid_or_missing_windows(self):
        self.render()
        previous = self.dest.stat()
        for payload in (b"{}\n", b"bad\x00\n", PAYLOAD.replace(b'"used_percentage":0', b'"used_percentage":101')):
            self.render(payload)
            self.assertEqual(self.dest.stat().st_ino, previous.st_ino)
            self.assertEqual(self.dest.stat().st_mtime_ns, previous.st_mtime_ns)

    def test_nondefault_profile_never_publishes_to_default_login_feed(self):
        self.env["CLAUDE_CONFIG_DIR"] = str(self.home / "other-profile")
        self.render()
        self.assertFalse(self.dest.exists())

    def test_write_failure_does_not_change_renderer(self):
        self.state.touch()
        self.render()
        self.assertFalse(self.dest.exists())

    def test_ignores_relative_xdg_state_home(self):
        self.env["XDG_STATE_HOME"] = "relative"
        self.render()
        self.assertTrue((self.home / ".local/state/jagpi/test-instance/claude-statusline.json").is_file())
