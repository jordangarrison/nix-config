#!/usr/bin/env python3
"""Check newly published text without echoing its contents."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


BUILTIN = {
    "incident ID": r"INC-\d+",
    "ticket ID": r"SRE-\d+",
    "Slack ID": r"\b[CDGU]0[A-Z0-9]{8,10}\b",
    "Slack archive link": r"(?i)\bslack\.com/archives(?:/|\b)",
    "home directory": r"(?:(?<![\w./~-])|(?<=file://))/home/[A-Za-z0-9_][A-Za-z0-9_.-]*",
}
DIFF_OPTIONS = (
    "--no-color", "--no-ext-diff", "--no-textconv", "--find-renames",
    "--src-prefix=a/", "--dst-prefix=b/", "--unified=0", "--inter-hunk-context=0",
)
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")


class CheckError(Exception):
    pass


def git(*args):
    result = subprocess.run(
        ["git", "-c", "core.quotePath=false", *args], capture_output=True, check=False
    )
    if result.returncode:
        # Git errors may contain paths or revisions derived from the input.
        raise CheckError(f"git {args[0]} failed; check that the required history is available")
    return result.stdout.decode("utf-8", errors="surrogateescape")


def patterns():
    raw = dict(BUILTIN)
    for number, line in enumerate(os.environ.get("PRIVACY_PATTERNS", "").splitlines(), 1):
        if line.strip() and not line.lstrip().startswith("#"):
            raw[f"custom pattern {number}"] = line.strip()
    for name, expr in raw.items():
        try:
            yield name, re.compile(expr)
        except re.error:
            raise CheckError(f"invalid regular expression for {name}") from None


def allowlist():
    path = Path(__file__).with_name("allowlist.tsv")
    entries = set()
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        file, separator, digest = line.partition("\t")
        if not separator or not file or file.startswith('"') or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise CheckError(f"invalid allowlist entry on line {number}")
        entries.add((file, digest))
    return entries


def added_hunks(patch):
    """Yield (path, first new line, added lines) from a zero-context diff."""
    path = None
    start = None
    lines = []
    for line in patch.split("\n"):
        hunk = HUNK.match(line)
        if line.startswith("diff --git ") or hunk:
            if lines:
                yield path, start, lines
            lines = []
            start = int(hunk[1]) if hunk else None
            if start is None:
                path = None
        elif start is not None and line.startswith("+"):
            lines.append(line[1:])  # Includes content beginning with literal '+++ '.
        elif start is None and line.startswith("+++ "):
            path = line[4:].removesuffix("\t")
            # Allowlist keys are unquoted Git paths. Quoted paths can be reported,
            # but are never considered for an exception.
            if path.startswith("b/"):
                path = path[2:]
    if lines:
        yield path, start, lines


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
        diff_base = git("merge-base", base, head).strip()
        messages.extend([("PR title", pr["title"]), ("PR body", pr["body"] or "")])
    elif event_name == "push":
        diff_base = base = commit_sha(payload["before"])
        head = commit_sha(payload["after"])
    else:
        raise CheckError("expected a pull_request or push event")

    log = git("log", "-z", "--format=%H%x00%B", f"{base}..{head}", "--")
    if log:
        fields = log.removesuffix("\0").split("\0")
        messages.extend((f"commit {sha[:12]}", body) for sha, body in zip(fields[::2], fields[1::2]))
    return git("diff", *DIFF_OPTIONS, diff_base, head, "--"), messages


def privacy_findings(hunks, messages):
    rules = list(patterns())
    allowed = allowlist()
    for path, start, lines in hunks:
        # Don't echo a path if it matches a privacy rule itself.
        label = "file"
        if path and not any(expr.search(path) for _, expr in rules):
            label = ascii(path)
        for number, line in enumerate(lines, start):
            digest = hashlib.sha256(line.encode("utf-8", errors="surrogateescape")).hexdigest()
            if (path, digest) not in allowed:
                for name, expr in rules:
                    if expr.search(line):
                        yield f"{label}:{number}: {name}"
    for label, message in messages:
        for number, line in enumerate(message.splitlines(), 1):
            for name, expr in rules:
                if expr.search(line):
                    yield f"{label} line {number}: {name}"


def check_secrets(hunks):
    added_text = "\n\n".join("\n".join(lines) for _, _, lines in hunks)
    if not added_text:
        return False
    # No repo-provided configuration and no logs that can echo candidate text.
    with tempfile.TemporaryDirectory() as directory:
        result = subprocess.run(
            ["nix", "run", "nixpkgs#gitleaks", "--", "stdin", "--redact=100",
             "--ignore-gitleaks-allow", "--exit-code=42"],
            cwd=directory,
            input=added_text.encode("utf-8", errors="surrogateescape") + b"\n",
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
        )
    if result.returncode == 42:
        print("gitleaks: potential secret in added lines; review the diff locally", file=sys.stderr)
        return True
    if result.returncode:
        raise CheckError("gitleaks could not complete; check Nix and gitleaks locally")
    print("gitleaks: no findings in added lines")
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    event = modes.add_parser("event", help="read the GitHub Actions event payload")
    event.add_argument("--gitleaks", action="store_true")
    staged = modes.add_parser("staged", help="check staged lines and a proposed commit message")
    staged.add_argument("--message", type=Path)
    staged.add_argument("--gitleaks", action="store_true")
    args = parser.parse_args()

    try:
        if args.mode == "event":
            payload = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_bytes())
            patch, messages = event_inputs(os.environ["GITHUB_EVENT_NAME"], payload)
        else:
            patch = git("diff", *DIFF_OPTIONS, "--cached", "--")
            messages = [] if args.message is None else [
                ("commit message", args.message.read_text(errors="surrogateescape"))
            ]
        hunks = list(added_hunks(patch))
        findings = list(privacy_findings(hunks, messages))
        for finding in findings:
            print(f"privacy check: {finding}", file=sys.stderr)
        secrets_found = check_secrets(hunks) if args.gitleaks else False
    except CheckError as error:
        print(f"privacy check: {error}", file=sys.stderr)
        return 2
    except (KeyError, OSError, TypeError, ValueError):
        print("privacy check: could not read a required input", file=sys.stderr)
        return 2
    if not findings and not secrets_found:
        print("privacy check: no findings")
    return int(bool(findings) or secrets_found)


if __name__ == "__main__":
    sys.exit(main())
