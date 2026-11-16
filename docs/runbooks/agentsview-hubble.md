# Move the AgentsView archive to Hubble

## Scope and approval

Move the **whole** `/home/jordangarrison/.agentsview` directory to
`/mnt/hubble/agentsview` on endeavour. Keep all history, caches, configuration,
and identity files. Do not prune, compact, change the content policy, or touch
raw provider logs (`~/.pi/agent/sessions`, `~/.claude/projects`, Codex logs).
Never print `config.toml` values.

**This is a daytime maintenance task.** Preparation did not stop AgentsView,
copy its archive, or activate a new configuration. Get Jordan's approval for
the activation and its extra service restarts. Keep the old archive as
`~/.agentsview.pre-move` after validation; **do not delete it until Jordan
explicitly says to delete it**. There is no scheduled deletion.

The prepared Nix build passed. Its dry activation reported:

```text
would stop the following units: accounts-daemon.service, agentsview.service, polkit.service
would activate the configuration...
warning: would not apply UID change of user ‘gdm-greeter-2’ (60580 -> 60579) in /etc/passwd
warning: would not apply UID change of user ‘gdm-greeter-3’ (60581 -> 60580) in /etc/passwd
warning: would not apply UID change of user ‘gdm-greeter-4’ (60582 -> 60581) in /etc/passwd
would reload the following units: dbus-broker.service
would start the following units: accounts-daemon.service, agentsview.service, polkit.service
```

Inspection found no changed package versions. The extra service changes were
system-path references and D-Bus/polkit restart triggers. Still, they are outside
the archive move and were **not approved for overnight activation**. Repeat the
build and dry activation on the day; do not assume the list stays the same.

## Storage constraints and service guards

Hubble is currently NTFS3, mounted with `force`, UUID `06FE60D3FE60BD15`.
Its mount masks synthesize broadly readable file permissions; `rsync -a` does
not make it as private as the original mode-0700 directory. This storage choice
was accepted for this move. It is not an independent backup or protection from
a failed/disconnected drive. Do not change the filesystem or mount masks as
part of this task.

A disposable test on this mount passed WAL writes, read isolation, competing
writer exclusion in a separate process, reopen, and `PRAGMA integrity_check`.
Repeat the test if the filesystem or mount changes.

`modules/nixos/agentsview.nix` uses `AGENTSVIEW_DATA_DIR` and requires:

- `RequiresMountsFor=/mnt/hubble/agentsview`;
- `After=mnt-hubble.mount` and `BindsTo=mnt-hubble.mount`;
- `ConditionPathIsMountPoint=/mnt/hubble`;
- `ConditionPathExists=/mnt/hubble/agentsview/sessions.db`.

If the drive or archive is missing, the service must stay stopped, not create
an empty replacement on the root disk. Mount loss stops the service; it cannot
guarantee safety after surprise removal during a write. Stop AgentsView before
any planned unmount. Do not test unplugging a live archive. Do not start a
second daemon with a manual CLI command. If a CLI is needed, set both
`AGENTSVIEW_DATA_DIR=/mnt/hubble/agentsview` and `AGENTSVIEW_NO_DAEMON=1`.

## 1. Build and inspect, without activating

Use a clean checkout of the reviewed branch, and preserve any other local work.
Set `REPO` to that checkout. Keep verification output outside the repository.

```bash
REPO=/path/to/nix-config
CHECK="$HOME/.local/state/agentsview-hubble-move-$(date +%Y%m%d-%H%M%S)"
mkdir -m 700 "$CHECK"
cd "$REPO"
nh os build . --hostname endeavour --no-nom --out-link "$CHECK/result"
sudo "$(readlink -f "$CHECK/result")/bin/switch-to-configuration" dry-activate
findmnt --mountpoint /mnt/hubble -o TARGET,SOURCE,FSTYPE,UUID,OPTIONS
df -h / /mnt/hubble
systemctl status agentsview.service --no-pager
```

Check the expected UUID, a writable mount, sufficient free space, and all
activation effects with Jordan. Stop if the target directory already exists
unless it is a known, inspected partial copy from this same migration.

## 2. Stop the only writer and record the baseline

Record the existing HTTP history counts without printing session content:

```bash
python3 - <<'PY' > "$CHECK/api-before.json"
import json, urllib.request
with urllib.request.urlopen('http://127.0.0.1:8080/api/v1/stats', timeout=30) as r:
    d = json.load(r)
print(json.dumps({k: d[k] for k in ('session_count', 'message_count')}))
PY
sudo systemctl stop agentsview.service
systemctl show agentsview.service -p ActiveState -p MainPID
pgrep -a -x agentsview || true
```

Do not proceed unless the unit is inactive with `MainPID=0` and **no** other
AgentsView process is running. Also check for any other process holding files
in the archive (`lsof +D "$HOME/.agentsview"` if available). Do not kill an
unidentified process.

Capture stable SQL metadata and IDs, not transcript text:

```bash
python3 - <<'PY' > "$CHECK/db-before.json"
import json, sqlite3
from pathlib import Path
p = Path.home() / '.agentsview/sessions.db'
with sqlite3.connect(p.as_uri() + '?mode=ro', uri=True) as c:
    d = {
        'sessions': c.execute('select count(*) from sessions').fetchone()[0],
        'messages': c.execute('select count(*) from messages').fetchone()[0],
        'session_ids': [r[0] for r in c.execute('select id from sessions order by id')],
        'last_modified': c.execute('select max(local_modified_at) from sessions').fetchone()[0],
    }
print(json.dumps(d))
PY
```

Read-only SQLite access can touch its shared-memory sidecar. Close the reader
before making the copy. If copying or verification fails, leave the original
in place and restart the old service before any activation.

## 3. Copy while stopped, then verify every file and the database

```bash
test ! -e /mnt/hubble/agentsview
rsync -a "$HOME/.agentsview/" /mnt/hubble/agentsview/
sync -f /mnt/hubble/agentsview
```

Check all relative file names, logical sizes, and SHA-256 digests, including
WAL and cache files. Do not print configuration contents or its digest.
Perform this comparison **before** opening the copied database:

```bash
python3 - <<'PY'
import hashlib
from pathlib import Path
src = Path.home() / '.agentsview'
dst = Path('/mnt/hubble/agentsview')
def manifest(root):
    result = {}
    for p in root.rglob('*'):
        if p.is_symlink():
            raise RuntimeError('Inspect symlinks before continuing')
        if p.is_file():
            h = hashlib.sha256()
            with p.open('rb') as f:
                for chunk in iter(lambda: f.read(8 * 1024 * 1024), b''):
                    h.update(chunk)
            result[str(p.relative_to(root))] = (p.stat().st_size, h.hexdigest())
    return result
a, b = manifest(src), manifest(dst)
assert a == b, 'Copy differs: keep original and investigate'
print('All file sizes and SHA-256 digests match')
print('sessions.db SHA-256:', a['sessions.db'][1])
print('Total file bytes:', sum(size for size, _ in a.values()))
PY
python3 - <<'PY'
import sqlite3
from pathlib import Path
src = Path.home() / '.agentsview/sessions.db'
dst = Path('/mnt/hubble/agentsview/sessions.db')
with sqlite3.connect(dst.as_uri() + '?mode=ro', uri=True) as c:
    assert c.execute('pragma integrity_check').fetchall() == [('ok',)], 'Integrity check failed'
    c.execute('attach database ? as original', (src.as_uri() + '?mode=ro',))
    for table in ('sessions', 'messages'):
        assert c.execute(f'select count(*) from {table}').fetchone() == c.execute(
            f'select count(*) from original.{table}').fetchone(), table
    assert c.execute('select id from original.sessions except select id from sessions').fetchone() is None
print('Integrity check: ok; all sessions and message counts retained')
PY
```

If any check fails, do not activate and do not remove either copy. Start the
unchanged old service and investigate. Do not use `VACUUM`, prune, or a rebuild
to make a failed check pass.

## 4. Test, obtain switch approval, then switch

Do not run `test` before the verified copy is ready: it activates the new unit.
The repository requires **build → test → switch**, in that order, with explicit
approval for switch after build and test have passed.

```bash
cd "$REPO"
nh os test . --hostname endeavour --no-nom
```

Confirm that activation succeeded, the service uses the new archive, and the
HTTP history and ingestion checks below pass. Ask Jordan to approve the
persistent switch **after** the successful test. Then:

```bash
nh os switch . --hostname endeavour --no-nom
```

If the reviewed build or activation list changed, stop and reassess. Do not use
a temporary environment override as a substitute for the persistent Nix change.

## 5. Verify history and new ingestion for at least 30 minutes

```bash
sudo systemctl start agentsview.service
systemctl show agentsview.service -p MainPID -p Environment -p RequiresMountsFor \
  -p BindsTo -p After -p ConditionResult
systemctl status agentsview.service --no-pager
```

Check the actual process's open database files (for example, with `lsof -p
<PID>`); they must be under `/mnt/hubble/agentsview`, not the old directory.
Confirm the generated unit retains all mount and existing-file guards.

Compare `/api/v1/stats` with the recorded API baseline. The existing visible
session count must be retained; an increase from natural new sessions is valid.
Use `/api/v1/sessions` or the UI to confirm old history is served. Compare the
saved SQL session IDs and counts to read-only queries of the new database:
no old ID may be missing, and message history must be retained. SQL counts can
include sessions excluded from the UI; compare like with like.

Record the new process start time and the offset in the copied `debug.log`
after startup, so pre-move messages are not mistaken for new errors. Monitor
both `journalctl -u agentsview.service` and `/mnt/hubble/agentsview/debug.log`,
including rotated files, throughout a continuous window of at least 30 minutes.
Check for SQLite, I/O, WAL, locking, ingestion, or other errors and unexpected
restarts. Require actual successful provider syncs and evidence that natural
new sessions or new messages are ingested (new IDs / increased message counts /
new `local_modified_at` values). If no new activity arrives, extend observation;
an idle daemon alone is not proof of ingestion. Do not create or edit raw
provider logs as a test.

If any check fails, stop and follow rollback. Do not free space yet.

## 6. Retain the old copy; deletion is a separate decision

Only after all checks pass and no process uses the old directory:

```bash
test ! -e "$HOME/.agentsview.pre-move"
mv "$HOME/.agentsview" "$HOME/.agentsview.pre-move"
```

Keep this rollback copy. Do not create a new empty `~/.agentsview`, add an
unreviewed symlink, set a deletion timer, or delete the old archive. Record its
allocated and logical size, the verification evidence, and the new active path
for Jordan. **No disk space is reclaimed by the rename.** Only after Jordan
separately approves deletion may a later task recheck integrity/history,
confirm no process uses the retained copy, remove that exact copy, and report
the allocated bytes freed. Never delete raw provider logs.

## Rollback

Before activation, restarting the unchanged service restores use of
`~/.agentsview`. Leave the external copy for inspection.

After activation, stop AgentsView first. Preserve the external archive **and
its WAL**: it may contain new history that the old copy does not have. If the
old directory was renamed, restore its original name without overwriting any
unexpected replacement. Revert the Nix service path and its Hubble-specific
guards to the previous configuration, then follow the repository's guarded
build/test/switch flow to restore the old service. Do not leave an ephemeral
runtime override as the only rollback.

Start one service, verify it reads the original archive, and report the failure
and any pending new writes preserved on Hubble. Do not silently claim the old,
stale copy includes post-cutover history; reconcile or re-ingest those writes
from the preserved sources before declaring recovery complete. If the drive is
unavailable or its integrity is suspect, keep the service stopped until a safe
recovery path is agreed. Neither a failed migration nor rollback authorizes
deleting either archive.
