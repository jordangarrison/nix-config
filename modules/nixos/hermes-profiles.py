"""Apply the Nix-owned parts of Hermes-owned profile configs (services.hermes).

Hermes owns every profile's config.yaml, .env, SOUL.md, memories, sessions and auth, and the
dashboard/Desktop edit them. Nix owns only the settings the spec pins, each a leaf path such as
``mcp_servers.executor.url``, plus optionally a ``mcp-tokens`` link to the service profile's token
store. A missing config, or one still linked to a Nix-generated file, is first replaced by the
spec's seed. A ledger in each profile records what Nix last applied, so dropping a pin removes
exactly that leaf unless a person changed it since. Conflicts are reported and left untouched.

Usage: hermes-profiles.py SPEC.json  (see modules/nixos/hermes.nix)
"""
import json
import os
import sys
import tempfile
import time
from pathlib import Path

# Hermes's own YAML 1.1 reader/writer and profile gates, from the deployed package.
import hermes_yaml
from hermes_constants import PROFILE_ID_RE, named_profile_has_identity, named_profile_is_deleted

LEDGER = ".nix-hermes-profile.json"
# Earlier Nix generations linked config.yaml to one of these; such a link is not Hermes's state.
NIX_OWNED_LINK_PREFIXES = ("/run/hermes-service/", "/nix/store/")


class Conflict(Exception):
    pass


def log(profile, message):
    print(f"{profile}: {message}", flush=True)


def write_atomic(path, text, mode):
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.nix-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def leaves(tree, prefix=()):
    """``{path: value}`` for every non-mapping (or empty mapping) leaf of a nested mapping."""
    out = {}
    for key, value in tree.items():
        path = (*prefix, key)
        if isinstance(value, dict) and value:
            out.update(leaves(value, path))
        else:
            out[path] = value
    return out


def get_path(tree, path):
    for key in path:
        if not isinstance(tree, dict) or key not in tree:
            return None, False
        tree = tree[key]
    return tree, True


def set_path(tree, path):
    """Parent mapping for ``path``, creating missing parents; Conflict if one is not a mapping."""
    for depth, key in enumerate(path[:-1]):
        child = tree.setdefault(key, {})
        if not isinstance(child, dict):
            raise Conflict(f"{'.'.join(path[:depth + 1])} is not a mapping")
        tree = child
    return tree


def delete_path(tree, path):
    """Remove a leaf, then any parent mapping this left empty."""
    parents = []
    for key in path[:-1]:
        parents.append((tree, key))
        tree = tree[key]
    del tree[path[-1]]
    for parent, key in reversed(parents):
        if parent[key]:
            break
        del parent[key]


def seed_config(name, path, seed):
    """Install the seed when the profile has no config of its own yet."""
    if path.is_symlink():
        target = os.readlink(path)
        if not target.startswith(NIX_OWNED_LINK_PREFIXES):
            raise Conflict(f"config.yaml links to {target}; not writing through it")
        path.unlink()
        log(name, f"replaced the Nix-generated config link ({target}) with a Hermes-owned copy of the seed")
    elif path.exists():
        return
    else:
        log(name, "created config.yaml from the seed")
    write_atomic(path, hermes_yaml.safe_dump(seed, sort_keys=False), 0o600)


def apply_settings(name, profile, desired, owned, seed):
    """Return the leaves Nix owns afterwards. Writes config.yaml only on change."""
    path = profile / "config.yaml"
    if seed is not None:
        seed_config(name, path, seed)
    if not desired and not owned:
        return {}
    if path.is_symlink():
        raise Conflict("config.yaml is a symlink; not writing through it")
    if not path.is_file():
        raise Conflict("config.yaml is missing")
    original = path.read_text(encoding="utf-8-sig")
    try:
        config = hermes_yaml.safe_load(original) or {}
    except Exception as exc:
        raise Conflict(f"config.yaml does not parse ({type(exc).__name__}); not rewriting it")
    if not isinstance(config, dict):
        raise Conflict("config.yaml is not a mapping")

    changed = False
    for key, value in owned.items():
        if key in desired:
            continue
        leaf = tuple(json.loads(key))
        current, present = get_path(config, leaf)
        if present and current == value:
            delete_path(config, leaf)
            changed = True
            log(name, f"removed {'.'.join(leaf)} (no longer pinned)")
        elif present:
            log(name, f"left {'.'.join(leaf)}: changed since Nix applied it")
    for key, value in desired.items():
        leaf = tuple(json.loads(key))
        current, present = get_path(config, leaf)
        if present and current == value:
            continue
        set_path(config, leaf)[leaf[-1]] = value
        changed = True
        log(name, f"set {'.'.join(leaf)}")

    if changed:
        backups = profile / "backups" / "config"
        backups.mkdir(parents=True, exist_ok=True)
        backup = backups / f"config.yaml.pre-nix.{time.strftime('%Y%m%d-%H%M%S')}"
        write_atomic(backup, original, 0o400)
        write_atomic(path, hermes_yaml.safe_dump(config, sort_keys=False), path.stat().st_mode & 0o777)
        log(name, f"updated config.yaml; previous copy at {backup}")
    return dict(desired)


def apply_token_link(name, profile, shared, want, owned):
    """Return whether Nix owns the mcp-tokens link afterwards."""
    link = profile / "mcp-tokens"
    linked = link.is_symlink() and os.path.realpath(link) == os.path.realpath(shared)
    if not want:
        if owned and linked:
            link.unlink()
            log(name, "removed the shared mcp-tokens link; enroll this profile's own MCP OAuth")
        return False
    if linked:
        return True
    if link.is_symlink():
        raise Conflict(f"mcp-tokens links to {os.readlink(link)}, not {shared}; leaving it")
    if link.is_dir():
        if any(link.iterdir()):
            raise Conflict("mcp-tokens holds this profile's own tokens; move them aside, then restart hermes-profiles")
        link.rmdir()
    elif link.exists():
        raise Conflict("mcp-tokens is not a directory; leaving it")
    shared.mkdir(mode=0o700, exist_ok=True)
    tmp = profile / ".mcp-tokens.nix-link"
    tmp.unlink(missing_ok=True)
    tmp.symlink_to(shared)
    os.replace(tmp, link)
    log(name, f"linked mcp-tokens to {shared}")
    return True


def read_ledger(path):
    ledger = json.loads(path.read_text()) if path.is_file() else {}
    if "mcpServers" in ledger:  # first-generation ledger: whole mcp_servers entries
        legacy = {"mcp_servers": ledger.pop("mcpServers")}
        ledger["settings"] = {json.dumps(k): v for k, v in leaves(legacy).items()}
    return ledger


def main(spec_path):
    spec = json.loads(Path(spec_path).read_text())
    home = Path(spec["home"])
    root = home / "profiles"
    declared = spec["profiles"]
    # Named profiles dropped from Nix still carry a ledger; undo what Nix applied there.
    names = set(declared)
    if root.is_dir():
        names |= {p.name for p in root.iterdir() if (p / LEDGER).is_file()}

    failed = False
    for name in sorted(names, key=lambda n: (n != "default", n)):
        want = declared.get(name, {"settings": {}, "shareMcpTokens": False, "seed": None})
        if name == "default":
            profile = home
            if not profile.is_dir():
                log(name, "service home missing; skipped")
                continue
        else:
            profile = root / name
            if not PROFILE_ID_RE.match(name):
                log(name, "not a named-profile id; skipped")
                failed = True
                continue
            if not profile.is_dir() or not named_profile_has_identity(profile):
                log(name, f"profile not found; create it with `hermes-service profile create {name}`, then restart hermes-profiles")
                continue
            if named_profile_is_deleted(profile):
                log(name, "profile is deleted in Hermes; skipped")
                continue

        ledger_path = profile / LEDGER
        ledger = read_ledger(ledger_path)
        owned_settings = ledger.get("settings", {})
        owned_link = ledger.get("shareMcpTokens", False)
        desired = {json.dumps(k): v for k, v in leaves(want["settings"]).items()}
        try:
            owned_settings = apply_settings(name, profile, desired, owned_settings, want.get("seed"))
        except Conflict as exc:
            log(name, f"settings not applied: {exc}")
            failed = True
        if name != "default":
            try:
                owned_link = apply_token_link(name, profile, home / "mcp-tokens", want["shareMcpTokens"], owned_link)
            except Conflict as exc:
                log(name, f"mcp-tokens not linked: {exc}")
                owned_link = False
                failed = True

        if owned_settings or owned_link:
            state = {"settings": owned_settings, "shareMcpTokens": owned_link}
            if state != ledger:
                write_atomic(ledger_path, json.dumps(state, indent=2, sort_keys=True) + "\n", 0o600)
        else:
            ledger_path.unlink(missing_ok=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
