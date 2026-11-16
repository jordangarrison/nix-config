#!/usr/bin/env python3
"""Test the real NGWAF token-file guard using empty, non-secret fixtures."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

SCRIPT = (Path(__file__).resolve().parents[1] /
          'users/jordangarrison/skills/ngwaf-incident/scripts/ngwaf.sh')


class TokenFilePermissions(unittest.TestCase):
    def setUp(self):
        source = SCRIPT.read_text()
        mode = re.search(r'^file_mode\(\).*$', source, re.M).group()
        guard = re.search(r'^assert_private\(\) \{.*?^\}', source, re.M | re.S).group()
        die = re.search(r'^die_code\(\).*$', source, re.M).group()
        self.functions = '\n'.join(['set -eu', 'EXIT_AUTH=4', die, mode, guard])
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.target = self.root / 'empty-fixture'
        self.target.touch(mode=0o600)
        self.link = self.root / 'link'
        self.link.symlink_to(self.target)

    def check_guard(self, path, expected, bsd=False):
        # GNU stat is present on CI. Emulate BSD option parsing while still
        # reading the fixture's actual target permissions with GNU stat.
        shim = '''
stat() {
  if [ "$#" != 4 ] || [ "$1" != -L ]; then return 99; fi
  case "$2:$3" in
    -c:%a) return 1 ;;
    -f:%Lp) command stat -L -c %a "$4" ;;
    *) return 99 ;;
  esac
}
''' if bsd else ''
        result = subprocess.run(
            ['bash', '-c', self.functions + shim + '\nassert_private "$1"',
             'ngwaf-permission-test', str(path)], capture_output=True, text=True)
        self.assertEqual(result.returncode, expected, result.stderr)

    def test_private_regular_file(self):
        self.check_guard(self.target, 0)

    def test_private_symlink_target(self):
        self.check_guard(self.link, 0)

    def test_readonly_private_symlink_target(self):
        self.target.chmod(0o400)
        self.check_guard(self.link, 0)

    def test_public_regular_file_is_rejected(self):
        self.target.chmod(0o644)
        self.check_guard(self.target, 4)

    def test_public_symlink_target_is_rejected(self):
        self.target.chmod(0o644)
        self.check_guard(self.link, 4)

    def test_dangling_symlink_is_rejected(self):
        self.target.unlink()
        self.check_guard(self.link, 4)

    def test_bsd_stat_follows_private_symlink_target(self):
        self.check_guard(self.link, 0, bsd=True)

    def test_bsd_stat_rejects_public_symlink_target(self):
        self.target.chmod(0o644)
        self.check_guard(self.link, 4, bsd=True)


if __name__ == '__main__':
    unittest.main()
