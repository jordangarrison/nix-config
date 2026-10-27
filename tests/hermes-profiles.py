"""Exercise the hermes-profiles unit's exact command: seeding, pins, and Hermes-owned edits."""
import json
import os
import shlex
import subprocess
import tempfile
from pathlib import Path

import hermes_yaml
from hermes_cli.config import _HERMES_HOME_SUBDIRS
from hermes_constants import profile_tombstone_path

command = shlex.split(os.environ["HERMES_TEST_PROFILES_EXEC"])
host_spec = json.loads(Path(os.environ["HERMES_TEST_PROFILES_SPEC"]).read_text())
host_default = host_spec["profiles"]["default"]
pins, seed = host_default["settings"], host_default["seed"]
assert set(pins) == {"agent", "auth", "dashboard", "mcp_servers", "skills"}
assert {"executor", "executor-flo"} <= set(pins["mcp_servers"])
unit_env = dict(os.environ, PYTHONPATH=os.environ["HERMES_TEST_PROFILES_PYTHONPATH"])
unit_env.pop("HERMES_MANAGED", None)


def service_home():
    home = Path(tempfile.mkdtemp(dir=os.environ["TMPDIR"])) / "hermes-service"
    for subdir in _HERMES_HOME_SUBDIRS:
        (home / subdir).mkdir(parents=True, exist_ok=True)
    (home / "SOUL.md").write_text("You are JordanBot.\n")
    (home / ".env").write_text("SLACK_BOT_TOKEN=xoxb-offline-fixture\n")
    (home / "mcp-tokens").mkdir(mode=0o700)
    (home / "mcp-tokens" / "executor.json").write_text('{"access_token": "fixture"}\n')
    return home


def run(home, profiles=None):
    spec = home.parent / f"spec-{len(list(home.parent.glob('spec-*')))}.json"
    spec.write_text(json.dumps({"home": str(home), "profiles": host_spec["profiles"] if profiles is None else profiles}))
    return subprocess.run(command[:-1] + [str(spec)], env=unit_env, text=True, capture_output=True)


def config(home):
    return hermes_yaml.safe_load((home / "config.yaml").read_text())


def backups(profile):
    directory = profile / "backups" / "config"
    return sorted(directory.glob("config.yaml.pre-nix.*")) if directory.is_dir() else []


def hermes_save(home, script):
    """Edit the config the way the dashboard/Desktop does: Hermes's own writer, unmanaged."""
    subprocess.run(["python", "-c", "from hermes_cli.config import load_config, save_config\n" + script],
                   env=dict(unit_env, HERMES_HOME=str(home)), check=True, text=True, capture_output=True)


# 1. An empty service home gets the seed as a private, Hermes-owned file.
home = service_home()
result = run(home)
assert result.returncode == 0, result.stdout + result.stderr
assert not (home / "config.yaml").is_symlink() and (home / "config.yaml").stat().st_mode & 0o777 == 0o600
assert config(home) == seed
assert (home / "SOUL.md").read_text() == "You are JordanBot.\n"
assert (home / ".env").read_text() == "SLACK_BOT_TOKEN=xoxb-offline-fixture\n"
ledger = json.loads((home / ".nix-hermes-profile.json").read_text())
assert {tuple(json.loads(k)) for k in ledger["settings"]} >= {
    ("agent", "system_prompt"), ("mcp_servers", "executor", "url"), ("dashboard", "public_url")}
settled = (home / "config.yaml").read_bytes()
assert run(home).returncode == 0 and (home / "config.yaml").read_bytes() == settled and not backups(home)

# 2. Hermes's own writer can edit it (the dashboard's Save); unpinned edits survive the unit,
#    pinned leaves are restored, and a field added under a pinned server stays.
hermes_save(home, """
c = load_config()
c["platforms"]["slack"]["extra"]["strict_mention"] = True
c["mcp_servers"]["executor"]["url"] = "https://drifted.invalid/mcp"
c["mcp_servers"]["executor"]["tools"] = {"include": ["search"]}
c["mcp_servers"]["mine"] = {"url": "https://mine.invalid/mcp"}
save_config(c)
""")
result = run(home)
assert result.returncode == 0, result.stdout + result.stderr
after = config(home)
assert after["platforms"]["slack"]["extra"]["strict_mention"] is True
assert after["mcp_servers"]["executor"]["url"] == pins["mcp_servers"]["executor"]["url"]
assert after["mcp_servers"]["executor"]["tools"] == {"include": ["search"]}
assert after["mcp_servers"]["mine"] == {"url": "https://mine.invalid/mcp"}
assert len(backups(home)) == 1 and "set mcp_servers.executor.url" in result.stdout

# 3. Dropping a pin removes that leaf unless it was changed since; an edited one is left.
hermes_save(home, """
c = load_config()
c["dashboard"]["public_url"] = "https://edited.invalid"
save_config(c)
""")
unpinned = json.loads(json.dumps(host_spec["profiles"]))
del unpinned["default"]["settings"]["dashboard"]
del unpinned["default"]["settings"]["mcp_servers"]["executor-flo"]
result = run(home, unpinned)
assert result.returncode == 0, result.stdout + result.stderr
after = config(home)
assert "executor-flo" not in after["mcp_servers"] and "executor" in after["mcp_servers"]
assert after["dashboard"]["public_url"] == "https://edited.invalid" and "left dashboard.public_url" in result.stdout

# 4. A config still linked to a Nix-generated file is replaced by the seed; other links are not.
home = service_home()
(home / "config.yaml").symlink_to(os.environ["HERMES_TEST_CONFIG"])
result = run(home)
assert result.returncode == 0 and "replaced the Nix-generated config link" in result.stdout
assert not (home / "config.yaml").is_symlink() and config(home) == seed
home = service_home()
(home / "elsewhere.yaml").write_text("model: {default: mine}\n")
(home / "config.yaml").symlink_to(home / "elsewhere.yaml")
result = run(home)
assert result.returncode == 1 and "not writing through it" in result.stdout
assert (home / "elsewhere.yaml").read_text() == "model: {default: mine}\n"

# 5. An unreadable config is reported, never rewritten.
home = service_home()
(home / "config.yaml").write_text("agent: [unclosed\n")
result = run(home)
assert result.returncode == 1 and "does not parse" in result.stdout
assert (home / "config.yaml").read_text() == "agent: [unclosed\n"

# 6. Named profiles: only their pins and an optional shared token link, undone when dropped.
home = service_home()
bot = home / "profiles" / "bot"
for subdir in _HERMES_HOME_SUBDIRS:
    (bot / subdir).mkdir(parents=True, exist_ok=True)
(bot / "profile.yaml").write_text("description: Bot\n")
(bot / "config.yaml").write_text("agent: {system_prompt: Review PRs.}\n")
executor = {"executor": pins["mcp_servers"]["executor"]}
named = dict(host_spec["profiles"], bot={"settings": {"mcp_servers": executor}, "seed": None, "shareMcpTokens": True})
result = run(home, named)
assert result.returncode == 0, result.stdout + result.stderr
assert config(bot) == {"agent": {"system_prompt": "Review PRs."}, "mcp_servers": executor}
assert os.readlink(bot / "mcp-tokens") == str(home / "mcp-tokens")
result = run(home)
assert result.returncode == 0, result.stdout + result.stderr
assert config(bot) == {"agent": {"system_prompt": "Review PRs."}}
assert not (bot / "mcp-tokens").exists() and (home / "mcp-tokens" / "executor.json").is_file()
assert not (bot / ".nix-hermes-profile.json").exists()

# 7. A first-generation ledger (whole mcp_servers entries) still undoes cleanly.
(bot / "config.yaml").write_text(json.dumps({"mcp_servers": executor}))
(bot / ".nix-hermes-profile.json").write_text(json.dumps({"mcpServers": executor, "shareMcpTokens": False}))
assert run(home).returncode == 0 and config(bot) == {}

# 8. Missing or deleted profiles are not created or revived.
result = run(home, dict(host_spec["profiles"], ghost={"settings": {"mcp_servers": executor}, "seed": None, "shareMcpTokens": False}))
assert result.returncode == 0 and "profile not found" in result.stdout and not (home / "profiles" / "ghost").exists()
profile_tombstone_path(bot).mkdir(parents=True)
before = (bot / "config.yaml").read_bytes()
assert run(home, named).returncode == 0 and (bot / "config.yaml").read_bytes() == before

print("hermes-profiles: ok")
