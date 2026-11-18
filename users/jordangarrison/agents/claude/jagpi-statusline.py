"""Publish only Claude Code's two subscription windows before rendering its status line."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def publish(payload, instance):
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
    dest.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    # Same directory for atomic replacement. NamedTemporaryFile creates mode 0600.
    temp = tempfile.NamedTemporaryFile(mode="w", dir=dest.parent, delete=False)
    tmp = Path(temp.name)
    try:
        with temp:
            os.fchmod(temp.fileno(), 0o600)
            json.dump({"rate_limits": windows}, temp)
        os.replace(tmp, dest)
    finally:
        tmp.unlink(missing_ok=True)


def main():
    instance, *renderer = sys.argv[1:]
    payload = sys.stdin.buffer.read()
    try:
        publish(payload, instance)
    except (ValueError, RecursionError, OSError):
        # The optional feed must not break the status line or dump its raw input.
        pass
    return subprocess.run(renderer, input=payload, check=False).returncode


if __name__ == "__main__":
    sys.exit(main())
