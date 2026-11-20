# Gemini data drive on endeavour

Gemini is the internal Samsung 860 EVO 250 GB SATA SSD, now ext4 with UUID
`daefadb8-2bb3-4073-8fb8-d4820021506a`. Its old BitLocker partitions were wiped
with the owner's explicit approval. It is not the USB NTFS backup drive Hubble.

`hosts/endeavour/configuration.nix` mounts Gemini at `/mnt/gemini`. `nofail`
and a five-second device timeout allow boot without the drive. Maple and
agentsview require it, so neither writes a fallback store on the root disk.

- `/mnt/gemini/maple`: Maple's complete state, private to the `maple` user,
  bind-mounted at `/var/lib/maple`. See [Maple](maple.md).
- `/mnt/gemini/agentsview`: agentsview's database and derived session data,
  owned by `jordangarrison:users`, mode `0700` (systemd tmpfiles).

## One-time agentsview cutover

**Do this only during an approved deployment.** Disk preparation did not mount
Gemini, copy data, stop agentsview, or apply this configuration. The mount-only
change shipped separately in PR #192 before the service migrations.

agentsview's old `~/.agentsview` directory is on the **root ext4 disk**, not
NTFS. It currently uses about 13 GB. Moving it frees that space only **after**
the old copy is deleted; keep the old copy until Jordan explicitly approves
its removal. The source Claude/Codex session directories stay in Jordan's home.

1. Build the reviewed configuration first:

   ```sh
   nh os build . -H endeavour --no-nom
   ```

2. Verify the mount-only change has already shipped. Never format the drive
   again. Abort if Gemini is absent or the mounted UUID is different:

   ```sh
   findmnt --fstab --target /mnt/gemini
   findmnt -o TARGET,SOURCE,FSTYPE,UUID /mnt/gemini
   # Expected UUID: daefadb8-2bb3-4073-8fb8-d4820021506a
   ```

3. Record the current UI session count. Stop agentsview to get a consistent
   database copy; leave it stopped until configuration activation:

   ```sh
   sudo systemctl stop agentsview
   sudo install -d -m 0700 -o jordangarrison -g users /mnt/gemini/agentsview
   rsync -aHAX --info=progress2 ~/.agentsview/ /mnt/gemini/agentsview/
   # A dry comparison should report no remaining differences.
   rsync -aHAXn --itemize-changes ~/.agentsview/ /mnt/gemini/agentsview/
   ```

4. Run the normal guarded **test** activation, then verify both services.
   Test starts agentsview with the new data directory (and Maple with its
   empty store). Check agentsview's UI, its session count against step 3,
   and new session synchronization. Do not delete the original directory.

   ```sh
   nh os test . -H endeavour --no-nom
   sudo systemctl start agentsview
   systemctl status agentsview maple var-lib-maple.mount mnt-gemini.mount
   findmnt /mnt/gemini
   findmnt /var/lib/maple
   ```

5. Only after build and test pass and Jordan explicitly confirms:

   ```sh
   nh os switch . -H endeavour --no-nom
   ```

If verification fails, stop the new agentsview service before reverting to the
old configuration and old data path. Do not rsync a live database backwards.
New sessions indexed after cutover are not part of the retained original copy.
No cleanup command is provided: deleting the old copy is a separate decision.

## Usage

```sh
df -h /mnt/gemini
sudo du -sh /mnt/gemini/maple /mnt/gemini/agentsview
```

Revisit Maple's telemetry volume if its state passes about **150 GB**, leaving
room for agentsview and filesystem overhead. Neither service has a disk quota.
If Gemini fills, database/checkpoint writes can fail; do not delete live
ClickHouse or SQLite files. Stop the affected service and plan recovery with
Jordan. Removing configuration does not remove data.
