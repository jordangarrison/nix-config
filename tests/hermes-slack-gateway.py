"""Offline: the deployed Hermes gateway's Slack gates under JordanBot's seeded config.

HERMES_HOME is the service home seeded by the hermes-profiles unit command. Fake token shapes
only; no network.
"""
import asyncio
import json
import os
import socket
from pathlib import Path


def no_network(*args, **kwargs):
    raise AssertionError("Offline Hermes checks must not connect to the network")


socket.socket.connect = no_network
socket.create_connection = no_network

from gateway.config import Platform, load_gateway_config
from gateway.run import GatewayRunner
from gateway.session import SessionSource
from gateway.authz_mixin import GatewayAuthorizationMixin
from hermes_cli.profiles import profiles_to_serve
from types import SimpleNamespace
from plugins.platforms.slack.adapter import SlackAdapter

JORDAN = os.environ["SLACK_ALLOWED_USERS"]
assert JORDAN == "UQ69UGHKM"
CHANNEL, THREAD = "C0C6WQGNL73", "1792880869.000100"

config = load_gateway_config()
slack = config.platforms[Platform.SLACK]
assert slack.enabled
assert slack.extra["allowed_channels"] == []  # any channel the bot is in
assert slack.extra["reaction_triggers"] == ["jordanbot"]
assert slack.extra["allow_bots"] == "none" and slack.extra["reactions"] is True
assert slack.home_channel.chat_id == "D0CCDQ1JBNY"  # no "set a home channel" prompt per thread

# One bot: only the default profile, and nothing routes a chat elsewhere.
assert [name for name, _ in profiles_to_serve(multiplex=True)] == ["default"]
assert not config.profile_routes
runner = SimpleNamespace(config=config)
assert GatewayRunner._profile_name_for_source(
    runner, SessionSource(platform=Platform.SLACK, user_id=JORDAN, chat_id=CHANNEL, chat_type="group")) is None

adapter = SlackAdapter(slack)
adapter._bot_user_id = "UJORDANBOT"
BOT = "<@UJORDANBOT>"


def gate(channel, text, thread=None, ts="1792880869.000200", force=False):
    return asyncio.run(adapter._channel_gate_allows(
        channel_id=channel, routing_text=text, bot_uid="UJORDANBOT", is_mentioned=BOT in text,
        is_thread_reply=bool(thread and thread != ts), event_thread_ts=thread, user_id=JORDAN,
        team_id="T0123456789", is_dm=False, force_process=force))


assert adapter._reactions_enabled() and adapter._extra_flag("rich_blocks")
assert gate(CHANNEL, f"{BOT} review this PR")
assert gate("C0123456789", f"{BOT} review this PR")  # any channel it is in
assert not gate(CHANNEL, "review this PR")  # a new conversation needs a mention
# Once mentioned, it follows the thread without another mention.
adapter._mentioned_threads.add(THREAD)
assert gate(CHANNEL, "and this one?", thread=THREAD)
assert not gate(CHANNEL, "unrelated thread", thread="1792880869.000900")
# Other bots are ignored even when they mention JordanBot.
bot_event = {"user": "UOTHERBOT", "bot_id": "B0123456789", "text": f"{BOT} hi"}
assert asyncio.run(adapter._peer_bot_drop(bot_event, "UOTHERBOT", "UJORDANBOT", CHANNEL, "T0123456789", True))
# A :jordanbot: reaction becomes a turn from the reactor in the reacted-to thread.
assert adapter._slack_reaction_triggers() == {"jordanbot"}
reaction = adapter._synthetic_reaction_event(
    {"reaction": "jordanbot", "user": JORDAN, "item": {"channel": CHANNEL, "ts": "1792880869.000300"},
     "event_ts": "1792880869.000400"}, "added", "1792880869.000300", "T0123456789")
assert reaction["user"] == JORDAN and reaction["_hermes_force_process"]
assert reaction["text"] == "reaction:added:jordanbot" and reaction["thread_ts"] == "1792880869.000300"
assert gate(CHANNEL, reaction["text"], thread=reaction["thread_ts"], ts=reaction["ts"], force=True)


class AuthorizationProbe(GatewayAuthorizationMixin):
    def _adapter_profile_for_source(self, source):
        return None

    def _chat_scoped_grant(self, *args):
        return False

    def _pairing_store_for(self, source):
        return None

    def _adapter_resolved_allowlist_ids(self, source):
        return set()


# Only Jordan, in DMs and channels; a reaction's sender is the reactor.
probe = AuthorizationProbe()
for chat_id, chat_type in (("D0123456789", "dm"), (CHANNEL, "group"), ("C0123456789", "group")):
    for user_id, expected in ((JORDAN, True), ("UUNAUTHORIZED", False), ("UOTHERBOT", False), (None, False)):
        source = SessionSource(platform=Platform.SLACK, chat_id=chat_id, chat_type=chat_type, user_id=user_id)
        assert probe._principal_authorized(source, allow_adapter_delegation=False) is expected

print(json.dumps({"slack_gateway": "passed", "profile": "default only", "triggers": "mention, followed thread, :jordanbot:"}))
