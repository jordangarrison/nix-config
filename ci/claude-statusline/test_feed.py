"""Run with python3 -m unittest discover -s ci/claude-statusline."""

import json
import os
from pathlib import Path
import runpy
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

WRAPPER = (Path(__file__).resolve().parents[2] /
           "users/jordangarrison/agents/claude/jagpi-statusline.py")
RESET = int(time.time()) + 3600
PAYLOAD = b'''{
    "workspace":{"current_dir":"/not-published"},"session_id":"not-published",
    "rate_limits":{"five_hour":{"used_percentage":0,"resets_at":1800000000,
    "extra":"not-published"},"seven_day":{"used_percentage":true,"resets_at":1800000000},
    "spend_limit":{"used_percentage":33,"resets_at":1800000000}}
}\n\n'''.replace(b'1800000000', str(RESET).encode())


class StatuslineFeedTest(unittest.TestCase):
    def setUp(self):
        home = tempfile.TemporaryDirectory()
        self.addCleanup(home.cleanup)
        self.home = Path(home.name)
        self.state = self.home / "state"
        self.env = {"HOME": str(self.home), "XDG_STATE_HOME": str(self.state)}
        self.dest = self.state / "jagpi/test-instance/claude-statusline.json"
        self.onwatch = self.home / ".onwatch/data/anthropic-statusline.json"

    def render(self, payload=PAYLOAD, code=0, *, onwatch=False):
        flags = ["--onwatch"] if onwatch else []
        result = subprocess.run(
            [sys.executable, WRAPPER, *flags, "test-instance", sys.executable, "-c",
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
            "five_hour": {"used_percentage": 0, "resets_at": RESET},
        }})
        inode = self.dest.stat().st_ino
        self.render(PAYLOAD.replace(b'"used_percentage":0', b'"used_percentage":50'))
        self.assertNotEqual(self.dest.stat().st_ino, inode)
        self.assertEqual(list(self.dest.parent.iterdir()), [self.dest])
        self.assertEqual(json.loads(self.dest.read_bytes())["rate_limits"]["five_hour"]["used_percentage"], 50)
        self.assertFalse(self.onwatch.exists())

    def test_onwatch_enabled_publishes_both_feeds(self):
        self.render(onwatch=True)
        self.assertEqual(json.loads(self.dest.read_bytes()), {"rate_limits": {
            "five_hour": {"used_percentage": 0, "resets_at": RESET},
        }})
        self.assertEqual(self.onwatch.read_bytes(), PAYLOAD)
        self.assertEqual(stat.S_IMODE(self.onwatch.stat().st_mode), 0o600)

        inode = self.onwatch.stat().st_ino
        updated = PAYLOAD.replace(b'"used_percentage":0', b'"used_percentage":50')
        self.render(payload=updated, onwatch=True)
        self.assertNotEqual(self.onwatch.stat().st_ino, inode)
        self.assertEqual(self.onwatch.read_bytes(), updated)
        self.assertEqual(list(self.onwatch.parent.iterdir()), [self.onwatch])

    def test_does_not_replace_good_sample_on_invalid_or_missing_windows(self):
        self.render()
        previous = self.dest.stat()
        for payload in (b"{}\n", b"bad\x00\n", PAYLOAD.replace(b'"used_percentage":0', b'"used_percentage":101')):
            self.render(payload)
            self.assertEqual(self.dest.stat().st_ino, previous.st_ino)
            self.assertEqual(self.dest.stat().st_mtime_ns, previous.st_mtime_ns)

    def test_startup_before_first_reply_has_no_quota_to_publish(self):
        self.render(b'{"model":{},"context_window":{"current_usage":null}}')
        self.assertFalse(self.dest.exists())
        self.render()
        self.assertTrue(self.dest.is_file())

    def test_bad_reset_does_not_replace_the_last_observation(self):
        self.render()
        previous = self.dest.stat()
        for bad in (int(time.time()) - 1, RESET * 1000, RESET + 7 * 86400):
            with self.subTest(bad=bad):
                self.render(PAYLOAD.replace(str(RESET).encode(), str(bad).encode()))
                self.assertEqual(self.dest.stat().st_ino, previous.st_ino)

    def test_same_reset_is_valid_for_seven_day_but_not_five_hour(self):
        reset = int(time.time()) + 86400
        self.render(json.dumps({"rate_limits": {
            "five_hour": {"used_percentage": 11, "resets_at": reset},
            "seven_day": {"used_percentage": 22, "resets_at": reset},
        }}).encode())
        self.assertEqual(json.loads(self.dest.read_bytes()), {"rate_limits": {
            "seven_day": {"used_percentage": 22, "resets_at": reset},
        }})
        previous = self.dest.stat()
        self.render(json.dumps({"rate_limits": {
            "seven_day": {"used_percentage": 22, "resets_at": reset + 7 * 86400},
        }}).encode())
        self.assertEqual(self.dest.stat().st_ino, previous.st_ino)

    def test_each_reset_cutoff_includes_five_minutes_of_skew(self):
        publish = runpy.run_path(str(WRAPPER))["publish_jagpi"]
        now = 1_800_000_000
        with patch.dict(os.environ, self.env, clear=True), patch("time.time", return_value=now):
            for name, hours in (("five_hour", 5), ("seven_day", 7 * 24)):
                with self.subTest(window=name):
                    reset = now + hours * 3600 + 300
                    window = {"used_percentage": 10, "resets_at": reset}
                    publish(json.dumps({"rate_limits": {name: window}}), "test-instance")
                    self.assertEqual(json.loads(self.dest.read_bytes()), {"rate_limits": {name: window}})
                    previous = self.dest.stat()
                    publish(json.dumps({"rate_limits": {name: {**window, "resets_at": reset + 1}}}), "test-instance")
                    self.assertEqual(self.dest.stat().st_ino, previous.st_ino)

    def test_environment_auth_is_not_the_default_profile(self):
        for var in ("CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN",
                    "ANTHROPIC_BASE_URL", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX",
                    "CLAUDE_CODE_USE_FOUNDRY"):
            with self.subTest(var=var):
                self.env[var] = "synthetic"
                self.render()
                self.assertFalse(self.dest.exists())
                del self.env[var]

    def test_nondefault_profile_never_publishes_to_default_login_feed(self):
        self.env["CLAUDE_CONFIG_DIR"] = str(self.home / "other-profile")
        self.render()
        self.assertFalse(self.dest.exists())

    def test_jagpi_write_failure_does_not_block_onwatch(self):
        self.state.touch()
        self.render(onwatch=True)
        self.assertFalse(self.dest.exists())
        self.assertEqual(self.onwatch.read_bytes(), PAYLOAD)

    def test_onwatch_write_failure_does_not_block_jagpi(self):
        self.onwatch.parent.parent.touch()
        self.render(onwatch=True)
        self.assertTrue(self.dest.is_file())

    def test_ignores_relative_xdg_state_home(self):
        self.env["XDG_STATE_HOME"] = "relative"
        self.render()
        self.assertTrue((self.home / ".local/state/jagpi/test-instance/claude-statusline.json").is_file())
