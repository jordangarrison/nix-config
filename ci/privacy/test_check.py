import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


CHECK = Path(__file__).with_name("check.py").resolve()
REPO = CHECK.parents[2]
MARKER = "test scanner finding"


class PrivacyCheckTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.git("init", "--quiet")
        self.git("config", "user.name", "Synthetic Author")
        self.git("config", "user.email", "author@example.com")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "core.hooksPath", "/dev/null")
        self.write("existing.txt", f"legacy {MARKER}\nexisting text\n")
        self.base = self.commit(f"Baseline with old material: {MARKER}")
        self.write(".git/bin/nix", f'''#!/bin/sh
input=$(cat)
printf '%s\\n' "$input"
printf '%s\\n' "$input" >&2
if [ -n "$SCANNER_STATUS" ]; then exit "$SCANNER_STATUS"; fi
case "$input" in
    *'{MARKER}'*) exit 42 ;;
    *) exit 0 ;;
esac
''')
        (self.root / ".git/bin/nix").chmod(0o755)
        path = os.pathsep.join([str(self.root / ".git/bin"), os.environ.get("PATH", os.defpath)])
        self.scanner_env = {**os.environ, "PATH": path, "SCANNER_STATUS": ""}

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True).strip()

    def write(self, path, content):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "--quiet", "--allow-empty", "-m", message)
        return self.git("rev-parse", "HEAD")

    def check(self, *args, real_scanner=False, **env):
        return subprocess.run(
            [sys.executable, CHECK, *args], cwd=self.root, text=True,
            env={**(os.environ if real_scanner else self.scanner_env), **env}, capture_output=True,
        )

    def event(self, name, payload):
        path = self.root / ".git/event.json"
        path.write_text(json.dumps(payload))
        return self.check("event", GITHUB_EVENT_NAME=name, GITHUB_EVENT_PATH=str(path))

    def pr(self, head, *, base=None, title="Generic title", body=None):
        return self.event("pull_request", {"pull_request": {
            "base": {"sha": base or self.base}, "head": {"sha": head}, "title": title, "body": body,
        }})

    def assert_finding(self, result, sample=MARKER):
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("possible credential in new text", result.stderr)
        self.assertNotIn(sample, result.stdout + result.stderr)

    def test_added_line_is_scanned_even_with_leading_plus_signs(self):
        self.write("existing.txt", f"legacy {MARKER}\nexisting text\n+++ {MARKER}\n")
        self.assert_finding(self.pr(self.commit("Add text")))

    def test_unchanged_and_deleted_lines_pure_renames_and_old_messages_are_ignored(self):
        self.write("existing.txt", f"legacy {MARKER}\nclean edit\n")
        self.assertEqual(self.pr(self.commit("Clean edit")).returncode, 0)
        self.git("mv", "existing.txt", "renamed file.txt")
        self.assertEqual(self.pr(self.commit("Rename file")).returncode, 0)
        self.write("renamed file.txt", "clean edit\n")
        self.assertEqual(self.pr(self.commit("Remove old material")).returncode, 0)

    def test_pr_title_body_and_commit_messages_are_scanned_without_file_changes(self):
        self.assert_finding(self.pr(self.base, title=MARKER))
        self.assert_finding(self.pr(self.base, body=MARKER))
        flagged = self.commit(f"Some text\n\n{MARKER}")
        head = self.commit("More text")
        self.assert_finding(self.pr(head))
        self.assert_finding(self.event("push", {"before": self.base, "after": head}))
        self.assertEqual(self.event("push", {"before": flagged, "after": head}).returncode, 0)

    def test_pr_uses_merge_base_and_push_uses_before_and_after(self):
        self.write("existing.txt", "Sanitized on the base branch.\n")
        advanced_base = self.commit("Sanitize historical content")
        self.git("switch", "--detach", self.base)
        self.write("new.txt", "Clean addition.\n")
        head = self.commit("Clean PR commit")
        self.assertEqual(self.pr(head, base=advanced_base).returncode, 0)
        self.assert_finding(self.event("push", {"before": advanced_base, "after": head}))

    def test_staged_check_reads_index_and_message(self):
        self.write("changes.txt", "Clean when staged.\n")
        self.git("add", "changes.txt")
        self.write("changes.txt", f"{MARKER}\n")
        self.assertEqual(self.check("staged").returncode, 0)
        self.write(".git/message", MARKER)
        self.assert_finding(self.check("staged", "--message", ".git/message"))
        self.git("add", "changes.txt")
        self.write("changes.txt", "Clean again.\n")
        self.assert_finding(self.check("staged"))

    def test_hook_ignores_the_verbose_diff_but_checks_the_proposed_message(self):
        self.write("ci/privacy/check.py", CHECK.read_text())
        self.write("flake.lock", (REPO / "flake.lock").read_text())
        self.write(".githooks/commit-msg", "")
        shutil.copy2(REPO / ".githooks/commit-msg", self.root / ".githooks/commit-msg")
        self.git("config", "core.hooksPath", ".githooks")
        self.git("config", "core.commentString", "//")
        self.write("existing.txt", f"legacy {MARKER}\nclean edit\n")
        self.git("add", "existing.txt")

        def verbose_commit(message):
            return subprocess.run(
                ["git", "commit", "--edit", "--verbose", "-m", message],
                cwd=self.root, text=True, capture_output=True,
                env={**self.scanner_env, "GIT_EDITOR": ":"},
            )

        self.assert_finding(verbose_commit(MARKER))
        result = verbose_commit("Generic change")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("log", "-1", "--format=%B"), "Generic change")

    def test_missing_history_or_scanner_failure_fails_closed(self):
        self.assertEqual(self.event("push", {"before": "0" * 40, "after": self.base}).returncode, 2)
        self.write(".git/message", "Clean subject")
        status = self.check("staged", "--message", ".git/message", SCANNER_STATUS="3")
        self.assertEqual(status.returncode, 2, status.stderr)
        self.assertNotIn("Clean subject", status.stdout + status.stderr)

    @unittest.skipUnless(os.environ.get("PRIVACY_TEST_GITLEAKS") == "1", "requires Nix and Gitleaks")
    def test_pinned_gitleaks_scans_after_a_file_signature_and_ignores_inline_suppressions(self):
        credential = "_".join(["ghp", hashlib.sha256(b"synthetic only").hexdigest()[:36]])
        self.write("a-document.txt", "%PDF-1.7\n")
        self.git("add", "a-document.txt")
        self.write(".git/message", f"{credential} # gitleaks:allow\n")
        self.assert_finding(self.check("staged", "--message", ".git/message", real_scanner=True), credential)


if __name__ == "__main__":
    unittest.main()
