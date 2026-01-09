# Noctalia Shell Configuration

This directory contains shared noctalia-shell configuration for the Niri compositor across all hosts.

## What is Noctalia?

[Noctalia-shell](https://github.com/noctalia-dev/noctalia-shell) is a unified desktop shell for Wayland compositors, built on top of [quickshell](https://github.com/outfoxxed/quickshell). It provides:

- Status bar with system information
- Notification daemon
- Application launcher (Super+Space)
- Lock screen (Mod+Ctrl+Alt+L)
- Power menu

## Configuration Files

- **settings.json**: Main configuration (appearance, behavior, widgets)
- **colors.json**: Color scheme customization
- **plugins.json**: Plugin configuration and state
- **colorschemes/**: Custom color schemes (optional)
- **plugins/**: Custom plugins (optional)

## How This Works

### Symlink Setup

These configuration files are symlinked from `~/.config/noctalia/` to this directory via Home Manager:

```nix
# modules/home/niri/default.nix
xdg.configFile = {
  "noctalia/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink
      "${homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/configs/noctalia/settings.json";
  # ... (colors.json, plugins.json, etc.)
};
```

This means:
- `~/.config/noctalia/settings.json` → `~/dev/jordangarrison/nix-config/users/jordangarrison/configs/noctalia/settings.json`
- Changes to either location affect the same file
- Edits are immediately reflected in noctalia-shell
- Changes are tracked in git

### Live Editing

**Edit via noctalia UI:**
1. Use noctalia's built-in settings UI
2. Changes write to `~/.config/noctalia/settings.json`
3. Since it's a symlink, changes go to this repo
4. Run `git diff` to see changes
5. Commit and push to share with other hosts

**Edit directly in repo:**
1. Edit files in this directory
2. Noctalia-shell picks up changes immediately
3. Commit and push when ready

**No rebuild required!** Changes apply instantly without `nh os switch`.

## Sharing Across Hosts

### Initial Setup (Already Done)

Configuration was copied from endeavour:
```bash
scp -r 'endeavour:.config/noctalia/*' ~/.config/noctalia/
```

Then committed to this repo for sharing.

### Syncing Updates

**On any host:**
1. Make changes to noctalia config (via UI or direct edit)
2. `git add users/jordangarrison/configs/noctalia/`
3. `git commit -m "feat(noctalia): update xyz setting"`
4. `git push`

**On other hosts:**
1. `git pull`
2. Changes apply immediately (symlinks already point to repo)

## Multi-Desktop Setup

This configuration works alongside Hyprland without conflicts:

**Notification Daemon Handling:**
- Hyprland: Uses mako (started via `autostart.conf`)
- Niri: Uses noctalia-shell (started via `spawn-at-startup`)
- Mako systemd service is disabled to prevent conflicts

You can switch between desktops at login without issues.

## Customization

### Settings UI

Launch noctalia settings via the launcher or:
```bash
noctalia-shell ipc call settings toggle
```

### Manual Editing

Edit `settings.json` directly for advanced customization. Format is JSON with nested objects for each component.

### Color Schemes

Modify `colors.json` or add custom schemes to `colorschemes/` directory.

### Plugins

Add custom plugins to `plugins/` directory. See [noctalia documentation](https://github.com/noctalia-dev/noctalia-shell) for plugin development.

## Troubleshooting

**Noctalia not starting:**
```bash
# Check if running
pgrep quickshell

# View logs
journalctl --user -u niri -n 50 --no-pager | grep -i noctalia

# Restart manually
pkill quickshell && noctalia-shell &
```

**Notification conflicts:**
```bash
# Check for conflicting notification daemons
pgrep -a mako
pgrep -a dunst

# Kill conflicting daemon
pkill mako
```

**Config not updating:**
```bash
# Verify symlinks
ls -l ~/.config/noctalia/

# Should show symlinks to this repo, not regular files
```

## Resources

- [Noctalia GitHub](https://github.com/noctalia-dev/noctalia-shell)
- [Quickshell Documentation](https://github.com/outfoxxed/quickshell)
- [Niri Configuration](../../niri/default.nix)
