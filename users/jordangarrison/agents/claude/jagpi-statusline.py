"""Feed the enabled local quota trackers, then render Claude Code's status line."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def write_private(path, payload):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    # Write beside the destination so readers see a complete old or new sample.
    temp = tempfile.NamedTemporaryFile(dir=path.parent, delete=False)
    tmp = Path(temp.name)
    try:
        with temp:
            os.fchmod(temp.fileno(), 0o600)
            temp.write(payload)
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


def publish_jagpi(payload, instance):
    home = Path.home()
    profile = os.environ.get("CLAUDE_CONFIG_DIR")
    if profile and Path(os.path.abspath(profile)) != home / ".claude":
        return
    if any(os.environ.get(name) for name in (
        "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_BASE_URL", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX",
        "CLAUDE_CODE_USE_FOUNDRY",
    )):
        return

    data = json.loads(payload)
    limits = data.get("rate_limits") if isinstance(data, dict) else None
    if not isinstance(limits, dict):
        return
    windows = {}
    for name in ("five_hour", "seven_day"):
        window = limits.get(name)
        if not isinstance(window, dict):
            continue
        used, reset = window.get("used_percentage"), window.get("resets_at")
        if (type(used) in (int, float) and 0 <= used <= 100
                and type(reset) in (int, float) and 0 < reset <= 8640000000000):
            windows[name] = {"used_percentage": used, "resets_at": reset}
    if not windows:
        return

    state = Path(os.environ.get("XDG_STATE_HOME", ""))
    if not state.is_absolute():
        state = home / ".local" / "state"
    dest = state / "jagpi" / instance / "claude-statusline.json"
    write_private(dest, json.dumps({"rate_limits": windows}).encode("utf-8"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--onwatch", action="store_true")
    parser.add_argument("instance", help="jagpi instance, or an empty string to skip its feed")
    parser.add_argument("renderer", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    payload = sys.stdin.buffer.read()
    if args.onwatch:
        try:
            write_private(Path.home() / ".onwatch/data/anthropic-statusline.json", payload)
        except OSError:
            pass
    if args.instance:
        try:
            publish_jagpi(payload, args.instance)
        except (ValueError, RecursionError, OSError):
            pass
    # A feed failure must not break rendering or dump the raw input.
    return subprocess.run(args.renderer, input=payload, check=False).returncode


if __name__ == "__main__":
    sys.exit(main())
