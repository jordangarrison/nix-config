import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


CHECK = Path(__file__).with_name("check.py").resolve()
FIXTURE = Path("ci/privacy/fixtures/ticket.txt")
TICKET = (CHECK.parent / "fixtures/ticket.txt").read_text().strip()


class PrivacyCheckTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.git("init", "--quiet")
        self.git("config", "user.name", "Synthetic Author")
        self.git("config", "user.email", "author@example.com")
        self.git("config", "core.hooksPath", "/dev/null")
        self.write("existing.txt", f"legacy {TICKET}\nexisting text\n")
        self.base = self.commit("Baseline with old material")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True).strip()

    def write(self, path, content):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "--quiet", "--allow-empty", "-m", message)
        return self.git("rev-parse", "HEAD")

    def check(self, *args, **env):
        return subprocess.run(
            [sys.executable, CHECK, *args], cwd=self.root, text=True,
            env={**os.environ, "PRIVACY_PATTERNS": "", **env}, capture_output=True,
        )

    def event(self, name, payload, **env):
        path = self.root / ".git/event.json"
        path.write_text(json.dumps(payload))
        return self.check("event", GITHUB_EVENT_NAME=name, GITHUB_EVENT_PATH=str(path), **env)

    def pr(self, head, *, base=None, title="Generic title", body=None, **env):
        return self.event("pull_request", {"pull_request": {
            "base": {"sha": base or self.base}, "head": {"sha": head}, "title": title, "body": body,
        }}, **env)

    def assert_finding(self, result, location, sample=TICKET):
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(location, result.stderr)
        self.assertNotIn(sample, result.stdout + result.stderr)

    def test_added_line_is_blocked(self):
        self.write("existing.txt", f"legacy {TICKET}\nexisting text\n+++ {TICKET}_notes\n")
        self.assert_finding(self.pr(self.commit("Add text")), "'existing.txt':3: incident ID")

    def test_unchanged_and_deleted_lines_are_ignored(self):
        self.write("existing.txt", f"legacy {TICKET}\nclean edit\n")
        self.assertEqual(self.pr(self.commit("Clean edit")).returncode, 0)
        self.write("existing.txt", "clean edit\n")
        self.assertEqual(self.pr(self.commit("Remove old material")).returncode, 0)

    def test_body_and_title_are_checked(self):
        result = self.pr(self.base, title=TICKET, body=f"Details\n{TICKET}")
        self.assert_finding(result, "PR title line 1: incident ID")
        self.assertIn("PR body line 2: incident ID", result.stderr)

    def test_allowlist_is_bound_to_the_exact_path_and_line(self):
        self.write(FIXTURE, f"{TICKET}\n")
        self.assertEqual(self.pr(self.commit("Add synthetic fixture")).returncode, 0)
        self.write(FIXTURE, f"{TICKET}\nMore: {TICKET}\n")
        self.write("not-a-fixture.txt", f"{TICKET}\n")
        result = self.pr(self.commit("Add more text"))
        self.assert_finding(result, f"'{FIXTURE}':2: incident ID")
        self.assertIn("'not-a-fixture.txt':1: incident ID", result.stderr)
        self.assertNotIn(f"'{FIXTURE}':1: incident ID", result.stderr)

    def test_staged_check_reads_index_and_message(self):
        self.write("changes.txt", f"{TICKET}\n")
        self.assertEqual(self.check("staged").returncode, 0)
        self.git("add", "changes.txt")
        self.write("changes.txt", "Clean working tree content\n")
        self.write(".git/message", TICKET)
        result = self.check("staged", "--message", ".git/message")
        self.assert_finding(result, "'changes.txt':1: incident ID")
        self.assertIn("commit message line 1: incident ID", result.stderr)

    def test_commit_message_is_checked_on_pr_and_push(self):
        flagged = self.commit(f"Some text\n\n{TICKET}")
        head = self.commit("More text")
        for result in (self.pr(head), self.event("push", {"before": self.base, "after": head})):
            self.assert_finding(result, f"commit {flagged[:12]} line 3: incident ID")
        self.assertEqual(self.event("push", {"before": flagged, "after": head}).returncode, 0)

    def test_pr_ignores_changes_only_on_base_branch(self):
        head = self.commit("Clean PR commit")
        self.git("checkout", "--quiet", "--detach", self.base)
        self.write("unrelated.txt", f"{TICKET}\n")
        advanced_base = self.commit(f"Existing base change {TICKET}")
        self.assertEqual(self.pr(head, base=advanced_base).returncode, 0)

    def test_optional_patterns_are_used_without_echoing_the_values(self):
        site = "gateway.example.com"
        self.assertEqual(self.pr(self.base, body=site).returncode, 0)
        result = self.pr(self.base, body=site, PRIVACY_PATTERNS=r"\bgateway\.example\.com\b")
        self.assert_finding(result, "PR body line 1: custom pattern 1", sample=site)
        invalid = self.pr(self.base, PRIVACY_PATTERNS="[private text")
        self.assertEqual(invalid.returncode, 2)
        self.assertIn("invalid regular expression for custom pattern 1", invalid.stderr)
        self.assertNotIn("private text", invalid.stderr)

    def test_generic_patterns(self):
        cases = {
            "ticket ID": "SRE-" + "1234",
            "Slack ID": "C0" + "EXAMPLE12",
            "Slack archive link": "https://slack.com/" + "archives/example",
            "home directory": "/home/" + "example-user",
        }
        for rule, sample in cases.items():
            with self.subTest(rule=rule):
                self.assert_finding(self.pr(self.base, body=sample), f"PR body line 1: {rule}", sample)

    def test_relative_home_path_is_not_a_user_home(self):
        self.assertEqual(self.pr(self.base, body="See modules/home/example.").returncode, 0)
        sample = "file:///home/" + "example-user"
        self.assert_finding(self.pr(self.base, body=sample), "PR body line 1: home directory", sample)

    def test_pure_rename_does_not_recheck_unchanged_content(self):
        self.git("mv", "existing.txt", "renamed file.txt")
        self.assertEqual(self.pr(self.commit("Rename file")).returncode, 0)
