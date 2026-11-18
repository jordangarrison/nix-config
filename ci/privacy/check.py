#!/usr/bin/env python3
"""Scan new public text for credentials without echoing its contents."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


DIFF_OPTIONS = (
    "--no-color", "--no-ext-diff", "--no-textconv", "--find-renames",
    "--unified=0", "--inter-hunk-context=0", "--output-indicator-new=+",
)
# Git's scissors marker followed by its two explanatory comment lines. Match
# the repeated comment prefix instead of assuming English or the default '#'.
GIT_SCISSORS = re.compile(r"(?m)^(?P<prefix>[^\n]+?) -{24} >8 -{24}\n"
                          r"(?P=prefix) [^\n]*\n(?P=prefix) [^\n]*\n")


class CheckError(Exception):
    pass


def git(*args):
    result = subprocess.run(["git", *args], capture_output=True, check=False)
    if result.returncode:
        # Git errors may contain paths or revisions derived from the input.
        raise CheckError(f"git {args[0]} failed; check that the required history is available")
    return result.stdout.decode("utf-8", errors="surrogateescape")


def added_hunks(patch):
    """Yield only added text, preserving line breaks within each hunk."""
    lines = None
    for line in patch.split("\n"):
        if line.startswith(("diff --git ", "@@ ")):
            if lines:
                yield "\n".join(lines)
            lines = [] if line.startswith("@@ ") else None
        elif lines is not None and line.startswith("+"):
            lines.append(line[1:])  # Includes content beginning with literal '+++ '.
    if lines:
        yield "\n".join(lines)


def commit_sha(value):
    if not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", value) or not value.strip("0"):
        raise CheckError("event does not provide a nonzero commit SHA for both endpoints")
    return value


def event_inputs(event_name, payload):
    messages = []
    if event_name == "pull_request":
        pr = payload["pull_request"]
        base = commit_sha(pr["base"]["sha"])
        head = commit_sha(pr["head"]["sha"])
        comparison = f"{base}...{head}"
        title, body = pr["title"], pr["body"]
        if not isinstance(title, str) or (body is not None and not isinstance(body, str)):
            raise CheckError("event does not provide a valid PR title and body")
        messages.extend([title, body or ""])
    elif event_name == "push":
        base = commit_sha(payload["before"])
        head = commit_sha(payload["after"])
        comparison = f"{base}..{head}"
    else:
        raise CheckError("expected a pull_request or push event")

    log = git("log", "-z", "--format=%B", f"{base}..{head}", "--")
    messages.extend(log.split("\0"))
    return git("diff", *DIFF_OPTIONS, comparison, "--"), messages


def staged_inputs(message_path, hook_path):
    messages = []
    if path := message_path or hook_path:
        message = path.read_text(encoding="utf-8", errors="surrogateescape")
        if hook_path and (cut := GIT_SCISSORS.search(message)):
            message = message[:cut.start()]
        messages.append(message)
    return git("diff", *DIFF_OPTIONS, "--cached", "--"), messages


def gitleaks_installable():
    lock = json.loads((Path(__file__).resolve().parents[2] / "flake.lock").read_bytes())
    nodes = lock["nodes"]
    nixpkgs = nodes[lock["root"]]["inputs"]["nixpkgs"]
    rev = commit_sha(nodes[nixpkgs]["locked"]["rev"])
    return f"github:NixOS/nixpkgs/{rev}#gitleaks"


def check_secrets(sections):
    new_text = "\n\n".join(filter(None, sections))
    if not new_text:
        return False
    # A leading file signature can make Gitleaks skip the entire stream.
    scan_input = f"New text from Git changes:\n\n{new_text}\n"
    # Use bundled rules, not checkout files. Suppress all scanner output.
    with tempfile.TemporaryDirectory() as directory:
        result = subprocess.run(
            ["nix", "run", gitleaks_installable(), "--", "stdin", "--no-banner", "--redact=100",
             "--ignore-gitleaks-allow", "--exit-code=42"],
            cwd=directory, input=scan_input.encode("utf-8", errors="surrogateescape"),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
        )
    if result.returncode == 42:
        return True
    if result.returncode:
        raise CheckError("gitleaks could not complete; check Nix and gitleaks locally")
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    modes.add_parser("event", help="read the GitHub Actions event payload")
    staged = modes.add_parser("staged", help="check staged lines and a proposed commit message")
    message = staged.add_mutually_exclusive_group()
    message.add_argument("--message", type=Path, help="read literal commit message text")
    message.add_argument("--hook-message", type=Path, help="read the Git commit-msg hook input")
    args = parser.parse_args()

    try:
        if args.mode == "event":
            payload = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_bytes())
            patch, messages = event_inputs(os.environ["GITHUB_EVENT_NAME"], payload)
        else:
            patch, messages = staged_inputs(args.message, args.hook_message)
        if check_secrets([*added_hunks(patch), *messages]):
            print("privacy check: possible credential in new text; review the diff and messages locally", file=sys.stderr)
            return 1
    except CheckError as error:
        print(f"privacy check: {error}", file=sys.stderr)
        return 2
    except (KeyError, OSError, TypeError, ValueError):
        print("privacy check: could not read a required input", file=sys.stderr)
        return 2
    print("privacy check: no findings")
    return 0


if __name__ == "__main__":
    sys.exit(main())
