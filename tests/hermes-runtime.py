"""Offline compatibility checks against the exact Hermes package being deployed."""
import json
import os
import socket
import subprocess
from pathlib import Path


def no_network(*args, **kwargs):
    raise AssertionError("Offline Hermes checks must not connect to the network")


socket.socket.connect = no_network
socket.create_connection = no_network

from hermes_cli.config import load_config, is_managed
from hermes_cli.tools_config import _get_platform_tools
from gateway.config import load_gateway_config, Platform
from plugins.platforms.slack.adapter import SlackAdapter

config = load_config()
# Hermes owns the seeded config: no package-manager lock refusing dashboard writes.
assert not is_managed()
assert config["model"]["provider"] == "openai-codex"
assert config["auth"]["adopt_external_logins"] is False
assert not config["fallback_providers"]
from hermes_cli.personality import resolve_ephemeral_system_prompt

instructions = Path(os.environ["HERMES_TEST_INSTRUCTIONS"]).read_text().strip()
assert resolve_ephemeral_system_prompt(config) == instructions
assert config["skills"]["external_dirs"] == [
    str(Path(os.environ["HERMES_TEST_SERVICE_HOME"]).parents[2] / ".agents/skills")
]

# Exercise the real generated shell wrapper, intercepting only exec so the test
# never opens the operator's profile or provider credentials.
launcher_probe = subprocess.run([
    "bash", "-c",
    'exec() { printf "%s\\n" "$HERMES_HOME" "$HERMES_MANAGED" "$PWD" "$@"; }; '
    'source "$1" "${@:2}"',
    "launcher-test", os.environ["HERMES_TEST_LAUNCHER"], "chat", "argument with spaces",
], check=True, text=True, capture_output=True)
launcher_lines = launcher_probe.stdout.splitlines()
assert launcher_lines[:3] == [os.environ["HERMES_TEST_SERVICE_HOME"], "", os.getcwd()]
assert launcher_lines[-2:] == ["chat", "argument with spaces"]
for platform in ("slack", "cli", "cron"):
    selected = _get_platform_tools(config, platform)
    assert {"terminal", "file", "skills", "conduit"} <= selected, (platform, selected)

gateway = load_gateway_config()
assert gateway.get_unauthorized_dm_behavior(Platform.SLACK) == "ignore"
assert not gateway.platforms[Platform.API_SERVER].enabled
assert not gateway.platforms[Platform.WEBHOOK].enabled
slack = gateway.platforms[Platform.SLACK]
# The seeded JordanBot settings; tests/hermes-slack-gateway.py exercises their gates.
assert slack.enabled and slack.extra["allowed_channels"] == [] and slack.extra["allow_bots"] == "none"
assert slack.home_channel is not None and slack.home_channel.chat_id.startswith("D")

# Exercise the upstream allowlist algorithm without an initialized gateway,
# adapters, or pairing grants. No OAuth or Slack credentials are needed.
from gateway.authz_mixin import GatewayAuthorizationMixin
from gateway.session import SessionSource


class AuthorizationProbe(GatewayAuthorizationMixin):
    def _adapter_profile_for_source(self, source):
        return None

    def _chat_scoped_grant(self, *args):
        return False

    def _pairing_store_for(self, source):
        return None

    def _adapter_resolved_allowlist_ids(self, source):
        return set()


probe = AuthorizationProbe()
allowed = os.environ["SLACK_ALLOWED_USERS"].split(",")[0]
for user_id, expected in ((allowed, True), ("UUNAUTHORIZED", False), (None, False)):
    source = SessionSource(platform=Platform.SLACK, chat_id="D0123456789", chat_type="dm", user_id=user_id)
    assert probe._principal_authorized(source, allow_adapter_delegation=False) is expected

# Ensure the supported enrollment command can write the auth store in managed
# mode without trying to rewrite the Nix-owned config. Stub only the OAuth
# exchange: no real credential is created and no provider request is made.
from argparse import Namespace
from unittest.mock import AsyncMock, patch
from hermes_cli.auth_commands import auth_add_command

from dataclasses import replace
from hermes_cli.auth_commands import _OAUTH_ADD_SPECS

spec = replace(_OAUTH_ADD_SPECS["openai-codex"], login=lambda args: {
    "tokens": {"access_token": "offline-test-not-a-token", "refresh_token": "offline-test-not-a-refresh-token"}
})
with patch.dict(_OAUTH_ADD_SPECS, {"openai-codex": spec}):
    auth_add_command(Namespace(provider="openai-codex", auth_type="oauth", label="offline-test", priority=None))
assert Path(os.environ["HERMES_HOME"], "auth.json").exists()
# Enrollment may touch the Hermes-owned config; it must keep the repository's pins.
enrolled = load_config()
assert enrolled["mcp_servers"] == config["mcp_servers"]
assert resolve_ephemeral_system_prompt(enrolled) == instructions
# Desktop must expose coding tools and retain authenticated transport. Test both
# REST and WebSocket token gates without starting a server or calling a model.
from tui_gateway.server import _load_enabled_toolsets, _load_busy_input_mode
from hermes_cli.process_identity import is_desktop_owned_backend
from hermes_cli.web_server import app, _SESSION_TOKEN
from hermes_cli.web_server_chat import _ws_auth_reason
from starlette.testclient import TestClient
from starlette.websockets import WebSocket

assert {"terminal", "file", "skills", "conduit"} <= set(_load_enabled_toolsets("desktop"))
assert not is_desktop_owned_backend()
assert _load_busy_input_mode() == "steer"
from gateway.run import GatewayRunner
assert GatewayRunner._load_busy_input_mode() == "steer"
assert GatewayRunner._load_ephemeral_system_prompt().strip() == instructions
from tui_gateway.server import _startup_system_prompt
assert _startup_system_prompt(config, "offline-instructions").strip() == instructions
# Conduit is enabled alongside the standard coding tool bundles.
from hermes_cli.plugins import discover_plugins, get_plugin_manager
from model_tools import get_tool_definitions

discover_plugins()
conduit = next(p for p in get_plugin_manager().list_plugins() if p["name"] == "conduit_push")
assert conduit["enabled"] and not conduit["error"], conduit
assert conduit["version"] == "0.70.2"
assert conduit["hooks"] > 0, conduit
assert "conduit-push" in get_plugin_manager()._cli_commands
herdr_plugin = next(p for p in get_plugin_manager().list_plugins() if p["name"] == "herdr-agent-state")
assert herdr_plugin["enabled"] and not herdr_plugin["error"], herdr_plugin
assert herdr_plugin["hooks"] == 3, herdr_plugin
# Exercise the shipped integration without sending anything to a live pane.
import importlib.util

herdr_spec = importlib.util.spec_from_file_location(
    "herdr_probe", Path(os.environ["HERMES_TEST_PLUGINS"]) / "herdr-agent-state/__init__.py"
)
herdr_probe = importlib.util.module_from_spec(herdr_spec)
herdr_spec.loader.exec_module(herdr_probe)
with patch.object(herdr_probe.subprocess, "run") as report:
    with patch.dict(os.environ, {"HERDR_ENV": "0"}, clear=True):
        herdr_probe._session_started(platform="desktop", session_id="offline-session")
        report.assert_not_called()
    with patch.dict(os.environ, {"HERDR_ENV": "1", "HERDR_PANE_ID": "offline-pane"}, clear=True):
        herdr_probe._session_started(platform="slack", session_id="offline-session")
        report.assert_not_called()
        herdr_probe._session_started(platform="cli", session_id="offline-session")
        report.assert_called_once()
        argv = report.call_args.args[0]
        assert argv[:4] == ["herdr", "pane", "report-agent-session", "offline-pane"]
        assert argv[argv.index("--agent-session-id") + 1] == "offline-session"
definitions = get_tool_definitions(enabled_toolsets=_load_enabled_toolsets("desktop"), quiet_mode=True)
names = {definition["function"]["name"] for definition in definitions}
assert {"terminal", "read_file", "write_file", "patch", "search_files"} <= names, names
client = TestClient(app, base_url="http://127.0.0.1:9119")
assert client.get("/api/auth/me").status_code == 401
assert client.get("/api/auth/me", headers={"Authorization": "Bearer wrong"}).status_code == 401
assert client.get("/api/auth/me", headers={"Authorization": f"Bearer {_SESSION_TOKEN}"}).status_code == 200
for query, allowed in ((b"", False), (b"token=wrong", False), (f"token={_SESSION_TOKEN}".encode(), True)):
    ws = WebSocket({"type": "websocket", "path": "/api/ws", "query_string": query, "headers": [], "app": app}, receive=AsyncMock(), send=AsyncMock())
    assert (_ws_auth_reason(ws)[0] is None) is allowed
# Test real external-root resolution against an isolated fixture config. Never
# rewrite the Nix-generated config or touch the user's actual shared skills.
from agent import skill_utils

shared_fixture = Path(os.environ["HOME"]) / ".agents/skills"
shared_fixture.mkdir(parents=True)
fixture_config = Path(os.environ["HOME"]) / "skill-fixture.json"
fixture_config.write_text(json.dumps({"skills": {"external_dirs": [str(shared_fixture)]}}))
with patch.object(skill_utils, "get_config_path", return_value=fixture_config):
    skill_utils._external_dirs_cache_clear()
    assert skill_utils.get_external_skills_dirs() == [shared_fixture.resolve()]
    assert (skill_utils.TIER_EXTERNAL, shared_fixture.resolve()) in skill_utils.get_skill_search_roots(include_project=False)
skill_utils._external_dirs_cache_clear()
print(json.dumps({"config": "passed", "tools": "coding-enabled", "slack_gates": "passed", "oauth_enrollment": "passed", "desktop_auth": "passed", "shared_instructions": "passed", "shared_skills": "passed", "launcher": "passed", "herdr_hooks": "passed"}))
