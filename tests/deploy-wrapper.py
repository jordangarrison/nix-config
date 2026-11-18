"""Exercise deployment gates with fake nix/deploy/ssh; never contact a host."""
import json
import os
from pathlib import Path
import pty
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(sys.argv.pop(1)).resolve()
MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["MOCK_LOG"], "a") as log:
    log.write(json.dumps([name] + args) + "\n")
if name == "uname":
    print(os.environ.get("MOCK_HOST", "endeavour"))
elif name == "nix":
    if args[:2] == ["flake", "metadata"]:
        remote = any(a.startswith("git+ssh://git@github.com/jordangarrison/nix-config?") for a in args)
        if remote and os.environ.get("UNPUSHED_REV"):
            sys.exit(1)
        metadata = {"path": "/nix/store/fleet-snapshot", "revision": "a" * 40,
                    "locked": {"narHash": "sha256-same-source"}}
        if not remote and os.environ.get("DIRTY_SOURCE"):
            metadata.pop("revision")
        if remote and os.environ.get("SOURCE_MISMATCH"):
            metadata["locked"]["narHash"] = "sha256-other-source"
        if remote and os.environ.get("MISSING_HASH"):
            metadata["locked"].pop("narHash")
        print(json.dumps(metadata))
    elif args[0] == "build":
        sys.exit(int(os.environ.get("BUILD_FAIL", "0")))
    elif args[0] == "eval":
        print(json.dumps({"sshUser": "jordangarrison", "sshOpts": ["-o", "BatchMode=yes"],
                          "nodes": {"discovery": {"hostname": "discovery"},
                                    "endeavour": {"hostname": "localhost"}}}))
    else:
        raise AssertionError(args)
elif name == "ssh":
    mac = "jordan.garrison@h952l3dphh" in args
    if os.environ.get("SSH_FAIL") or (mac and os.environ.get("MAC_UNREACHABLE")):
        sys.exit(1)
    if mac and args[-1].startswith("nh darwin build "):
        sys.exit(int(os.environ.get("MAC_BUILD_FAIL", "0")))
    if mac and args[-1].startswith("nh darwin switch "):
        sys.exit(int(os.environ.get("MAC_SWITCH_FAIL", "0")))
    if mac and os.environ.get("BAD_MAC_PATH"):
        print("invalid")
    else:
        print("invalid" if os.environ.get("BAD_PATH") else "/nix/store/old-nixos-system")
elif name == "deploy":
    if (("--test" in args and os.environ.get("TEST_FAIL"))
            or ("--test" not in args and os.environ.get("LINUX_SWITCH_FAIL"))):
        sys.exit(1)
else:
    raise AssertionError(name)
'''


class DeploymentGates(unittest.TestCase):
    def run_wrapper(self, args=(), answer=b"n\n", interactive=True, **overrides):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bindir = root / "bin"
            bindir.mkdir()
            for name in ("uname", "nix", "ssh", "deploy"):
                command = bindir / name
                command.write_text(MOCK.replace("#!/usr/bin/env python3", f"#!{sys.executable}", 1))
                command.chmod(0o755)
            log = root / "calls.jsonl"
            env = dict(os.environ, PATH=f"{bindir}:{os.environ['PATH']}",
                       MOCK_LOG=str(log), XDG_STATE_HOME=str(root / "state"), **overrides)
            master, slave = pty.openpty()
            try:
                if interactive:
                    os.write(master, answer)
                result = subprocess.run(
                    ["bash", str(SCRIPT), *args], env=env,
                    stdin=slave if interactive else subprocess.DEVNULL,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    text=True, timeout=15,
                )
            finally:
                os.close(master)
                os.close(slave)
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            records = list((root / "state/nix-config/deploy").glob("before-*.txt"))
            record = records[0].read_text() if records else ""
            return result, calls, record

    def test_build_only_has_no_remote_effects(self):
        result, calls, _ = self.run_wrapper(["--build-only"], interactive=False)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(any(c[0] in ("ssh", "deploy") for c in calls))
        build = next(c for c in calls if c[:2] == ["nix", "build"])
        for check in ("deploy-schema", "deploy-activate", "deploy-policy", "deploy-wrapper"):
            self.assertIn(f"/nix/store/fleet-snapshot#checks.x86_64-linux.{check}", build)
        self.assertIn("--no-update-lock-file", build)

    def test_full_flow_uses_one_revision_and_mac_switches_last(self):
        result, calls, record = self.run_wrapper(answer=b"y\n")
        self.assertEqual(result.returncode, 0, result.stdout)
        deploys = [c for c in calls if c[0] == "deploy"]
        self.assertEqual(len(deploys), 2)
        self.assertIn("--test", deploys[0])
        self.assertNotIn("--test", deploys[1])
        for call in deploys:
            index = call.index("--targets")
            self.assertEqual(call[index + 1:index + 3], [
                "/nix/store/fleet-snapshot#discovery.system",
                "/nix/store/fleet-snapshot#endeavour.system",
            ])
            self.assertIn("--no-update-lock-file", call)
        names = [c[0] for c in calls]
        build_index = next(i for i, c in enumerate(calls) if c[:2] == ["nix", "build"])
        self.assertLess(build_index, names.index("ssh"))
        mac_build = next(i for i, c in enumerate(calls)
                         if c[0] == "ssh" and c[-1].startswith("nh darwin build "))
        mac_switch = next(i for i, c in enumerate(calls)
                          if c[0] == "ssh" and c[-1].startswith("nh darwin switch "))
        self.assertLess(mac_build, names.index("deploy"))
        self.assertGreater(mac_switch, max(i for i, n in enumerate(names) if n == "deploy"))
        url = "git+ssh://git@github.com/jordangarrison/nix-config?allRefs=1&rev=" + "a" * 40
        for index in (mac_build, mac_switch):
            self.assertIn("-t", calls[index])
            self.assertIn(f"'{url}'", calls[index][-1])
            self.assertIn("-H H952L3DPHH --no-nom --no-update-lock-file", calls[index][-1])
        self.assertIn("--elevation-strategy /usr/bin/sudo", calls[mac_switch][-1])
        published = next(c for c in calls if c[:2] == ["nix", "flake"] and url in c)
        self.assertIn("--refresh", published)
        self.assertIn("H952L3DPHH (jordan.garrison@h952l3dphh): /nix/store/old-nixos-system", record)
        self.assertIn("sudo env HOME=/var/root /nix/store/old-nixos-system/activate", record)
        self.assertIn("discovery (discovery): /nix/store/old-nixos-system", record)
        self.assertIn("endeavour (localhost): /nix/store/old-nixos-system", record)
        self.assertIn("switch-to-configuration switch", record)
        self.assertEqual(result.stdout.count("[y/N]"), 1)

    def test_declining_or_eof_never_switches(self):
        for answer in (b"n\n", b"\n", b"\x04", b"no\n"):
            with self.subTest(answer=answer):
                result, calls, _ = self.run_wrapper(answer=answer)
                self.assertEqual(result.returncode, 0, result.stdout)
                deploys = [c for c in calls if c[0] == "deploy"]
                self.assertEqual(len(deploys), 1)
                self.assertIn("--test", deploys[0])
                self.assertIn("Live tests remain active", result.stdout)
                self.assertFalse(any(c[0] == "ssh" and c[-1].startswith("nh darwin switch ") for c in calls))

    def test_failed_build_never_contacts_a_target(self):
        result, calls, _ = self.run_wrapper(BUILD_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c[0] in ("ssh", "deploy") for c in calls))

    def test_failed_preflight_never_deploys(self):
        for overrides in ({"SSH_FAIL": "1"}, {"BAD_PATH": "1"}):
            with self.subTest(overrides=overrides):
                result, calls, _ = self.run_wrapper(**overrides)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(c[0] == "deploy" for c in calls))

    def test_failed_test_never_prompts_or_switches(self):
        result, calls, _ = self.run_wrapper(answer=b"y\n", TEST_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len([c for c in calls if c[0] == "deploy"]), 1)
        self.assertNotIn("[y/N]", result.stdout)

    def test_noninteractive_caller_is_local_only(self):
        result, calls, _ = self.run_wrapper(interactive=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c[0] in ("ssh", "deploy") for c in calls))

    def test_mac_can_be_skipped_without_source_or_reachability_checks(self):
        result, calls, _ = self.run_wrapper(["--no-mac"], answer=b"y\n",
                                             DIRTY_SOURCE="1", UNPUSHED_REV="1", MAC_UNREACHABLE="1")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(len([c for c in calls if c[0] == "deploy"]), 2)
        self.assertFalse(any("jordan.garrison@h952l3dphh" in c for c in calls))
        self.assertEqual(len([c for c in calls if c[:3] == ["nix", "flake", "metadata"]]), 1)
        self.assertIn("Mac excluded by --no-mac", result.stdout)

    def test_build_only_accepts_dirty_sources_and_flag_orders(self):
        for args in (["--no-mac", "--build-only"], ["--build-only", "--no-mac"], ["--build-only"]):
            with self.subTest(args=args):
                result, calls, _ = self.run_wrapper(args, interactive=False, DIRTY_SOURCE="1")
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertFalse(any(c[0] in ("ssh", "deploy") for c in calls))

    def test_unpublished_or_different_sources_refused_before_live_work(self):
        for overrides in ({"DIRTY_SOURCE": "1"}, {"UNPUSHED_REV": "1"},
                          {"SOURCE_MISMATCH": "1"}, {"MISSING_HASH": "1"}):
            with self.subTest(overrides=overrides):
                result, calls, _ = self.run_wrapper(**overrides)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(c[0] in ("ssh", "deploy") for c in calls))

    def test_mac_preflight_or_build_failure_prevents_linux_live_tests(self):
        for overrides in ({"MAC_UNREACHABLE": "1"}, {"BAD_MAC_PATH": "1"}, {"MAC_BUILD_FAIL": "1"}):
            with self.subTest(overrides=overrides):
                result, calls, _ = self.run_wrapper(**overrides)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(c[0] == "deploy" for c in calls))
                self.assertNotIn("[y/N]", result.stdout)
        self.assertIn("--no-mac", self.run_wrapper(MAC_UNREACHABLE="1")[0].stdout)

    def test_linux_switch_failure_never_switches_mac(self):
        result, calls, _ = self.run_wrapper(answer=b"y\n", LINUX_SWITCH_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c[0] == "ssh" and c[-1].startswith("nh darwin switch ") for c in calls))

    def test_mac_switch_failure_is_loud_without_linux_rollback(self):
        result, calls, _ = self.run_wrapper(answer=b"y\n", MAC_SWITCH_FAIL="23")
        self.assertEqual(result.returncode, 23, result.stdout)
        self.assertEqual(len([c for c in calls if c[0] == "deploy"]), 2)
        self.assertIn("Linux switches remain applied; no Linux rollback attempted", result.stdout)

    def test_wrong_machine_and_unknown_options_fail_closed(self):
        for args, overrides in (((), {"MOCK_HOST": "discovery"}),
                                (("--yes",), {}), ((".", "extra"), {})):
            with self.subTest(args=args, overrides=overrides):
                result, calls, _ = self.run_wrapper(args=args, **overrides)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(c[0] in ("ssh", "deploy") for c in calls))


if __name__ == "__main__":
    unittest.main()
