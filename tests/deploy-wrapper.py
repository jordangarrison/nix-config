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
        print(json.dumps({"path": "/nix/store/fleet-snapshot"}))
    elif args[0] == "build":
        sys.exit(int(os.environ.get("BUILD_FAIL", "0")))
    elif args[0] == "eval":
        print(json.dumps({"sshUser": "jordangarrison", "sshOpts": ["-o", "BatchMode=yes"],
                          "nodes": {"discovery": {"hostname": "discovery"},
                                    "endeavour": {"hostname": "localhost"}}}))
    else:
        raise AssertionError(args)
elif name == "ssh":
    if os.environ.get("SSH_FAIL"):
        sys.exit(1)
    print("invalid" if os.environ.get("BAD_PATH") else "/nix/store/old-nixos-system")
elif name == "deploy":
    if "--test" in args and os.environ.get("TEST_FAIL"):
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

    def test_full_flow_uses_one_snapshot_and_workstation_last(self):
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
        self.assertLess(max(i for i, n in enumerate(names) if n == "ssh"), names.index("deploy"))
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

    def test_wrong_machine_and_unknown_options_fail_closed(self):
        for args, overrides in (((), {"MOCK_HOST": "discovery"}),
                                (("--yes",), {}), ((".", "extra"), {})):
            with self.subTest(args=args, overrides=overrides):
                result, calls, _ = self.run_wrapper(args=args, **overrides)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(c[0] in ("ssh", "deploy") for c in calls))


if __name__ == "__main__":
    unittest.main()
