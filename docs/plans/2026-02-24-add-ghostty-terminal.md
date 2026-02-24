# Add Ghostty Terminal Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Ghostty terminal emulator via flake input and make it the default terminal across all environments (Niri, GNOME, Hyprland), matching the current Alacritty look and feel with built-in rose-pine theme.

**Architecture:** Add Ghostty as a flake input from `github:ghostty-org/ghostty`, install via Home Manager, configure to match Alacritty's settings (font, opacity, padding, decorations), create a Ghostty apps module for desktop entries, and replace all Alacritty/WezTerm default terminal references.

**Tech Stack:** Nix Flakes, Home Manager, Ghostty config format (INI-style key=value)

---

### Task 1: Add Ghostty Flake Input

**Files:**
- Modify: `flake.nix:4-51` (inputs section)
- Modify: `flake.nix:54-72` (outputs function args)

**Step 1: Add ghostty to flake inputs**

In `flake.nix`, add after the `greenlight` input (line 50):

```nix
ghostty = {
  url = "github:ghostty-org/ghostty";
};
```

**Step 2: Add ghostty to outputs function args**

In `flake.nix` line 72, add `ghostty` to the destructured inputs:

```nix
outputs =
  inputs@{
    self,
    nixpkgs,
    nixpkgs-stable,
    nixpkgs-master,
    nixos-hardware,
    nix-darwin,
    home-manager,
    nvf,
    aws-tools,
    aws-use-sso,
    hubctl,
    llm-agents,
    niri,
    noctalia,
    sweet-nothings,
    nix-zed-extensions,
    greenlight,
    ghostty,
  }:
```

**Step 3: Verify flake evaluates**

Run: `nix flake check --no-build 2>&1 | head -20`
Expected: No errors about unknown inputs

**Step 4: Commit**

```bash
git add flake.nix
git commit -m "feat(ghostty): add ghostty flake input"
```

---

### Task 2: Update Ghostty Config File

**Files:**
- Modify: `users/jordangarrison/tools/ghostty/config`

**Step 1: Write the Ghostty config matching Alacritty settings**

Replace the contents of `users/jordangarrison/tools/ghostty/config` with:

```ini
# Font
font-family = Source Code Pro
font-size = 10

# Window
window-decoration = none
maximize = true
background-opacity = 0.80
window-padding-x = 5
window-padding-y = 5

# Theme (built-in rose-pine)
theme = rose-pine

# Shell integration
shell-integration = zsh

# Keybindings
# Shift+Enter sends newline for Claude Code multiline input
keybind = shift+enter=text:\n

# GTK
gtk-titlebar = false
```

**Step 2: Commit**

```bash
git add users/jordangarrison/tools/ghostty/config
git commit -m "feat(ghostty): configure ghostty matching alacritty look and feel"
```

---

### Task 3: Install Ghostty Package and Link Config

**Files:**
- Modify: `users/jordangarrison/home.nix:70-239` (home.packages)
- Modify: `users/jordangarrison/home.nix:638-706` (home.file)

**Step 1: Add ghostty package to home.packages**

In `users/jordangarrison/home.nix`, in the Linux-only packages section (the `else` block starting around line 203), add:

```nix
inputs.ghostty.packages.${pkgs.system}.default
```

Add it near the other flake input packages (around line 237, near `inputs.hubctl`).

**Step 2: Link ghostty config via home.file**

In `users/jordangarrison/home.nix`, in the `home.file` section, add after the wezterm config (around line 695):

```nix
# Ghostty terminal configuration
".config/ghostty/config".source = ./tools/ghostty/config;
```

**Step 3: Commit**

```bash
git add users/jordangarrison/home.nix
git commit -m "feat(ghostty): install ghostty package and link config"
```

---

### Task 4: Create Ghostty Apps Module

**Files:**
- Create: `modules/home/ghostty/apps.nix`

**Step 1: Create the ghostty apps module**

Create `modules/home/ghostty/apps.nix` mirroring the alacritty apps module (`modules/home/alacritty/apps.nix`) but using `ghostty -e`:

```nix
{ lib, pkgs, config, inputs, ... }:

with lib;

let
  cfg = config.ghosttyApps;
  ghosttyPkg = inputs.ghostty.packages.${pkgs.system}.default;

  # Create wrapper scripts for each app
  wrapperScripts = listToAttrs (map
    (app:
      let
        appId = toLower (replaceStrings [ " " ] [ "-" ] app.name);
        scriptName = "ghostty-${appId}";
        script = pkgs.writeShellScript scriptName ''
          exec ${ghosttyPkg}/bin/ghostty --class="${app.name}" --title="${app.name}" -e ${escapeShellArg app.command}
        '';
      in
      nameValuePair appId script
    )
    cfg.apps);

  apps = listToAttrs (map
    (app:
      let
        appId = toLower (replaceStrings [ " " ] [ "-" ] app.name);
        iconName =
          if (builtins.typeOf app.icon == "path")
          then appId
          else app.icon;
        script = wrapperScripts.${appId};
      in
      nameValuePair appId {
        name = app.name;
        exec = "${script}";
        icon = iconName;
        type = "Application";
        categories = app.categories;
        comment = "${app.name} Terminal App";
        settings = {
          StartupWMClass = app.name;
        };
      }
    )
    cfg.apps);
in
{
  options.ghosttyApps.apps = mkOption {
    type = types.listOf (types.submodule {
      options = {
        name = mkOption {
          type = types.str;
          description = "Display name of the terminal app.";
        };
        command = mkOption {
          type = types.str;
          description = "Command to run in the terminal.";
        };
        categories = mkOption {
          type = types.listOf types.str;
          default = [ "System" ];
          description = "Desktop categories for the terminal app.";
        };
        icon = mkOption {
          type = types.either types.str types.path;
          default = "utilities-terminal";
          description = "Icon name for the desktop entry.";
        };
      };
    });
    default = [ ];
    description = "List of terminal applications to create with Ghostty.";
  };

  config = {
    xdg.desktopEntries = apps;
  };
}
```

**Step 2: Commit**

```bash
git add modules/home/ghostty/apps.nix
git commit -m "feat(ghostty): create ghostty apps module for desktop entries"
```

---

### Task 5: Switch home-linux.nix to Use Ghostty

**Files:**
- Modify: `users/jordangarrison/home-linux.nix:4-12` (imports)
- Modify: `users/jordangarrison/home-linux.nix:90-101` (GNOME favorites)
- Modify: `users/jordangarrison/home-linux.nix:126-137` (auto-move-windows)
- Modify: `users/jordangarrison/home-linux.nix:161-169` (alacrittyApps → ghosttyApps)

**Step 1: Add ghostty apps import**

In the imports list (line 7), replace the alacritty import:

Change:
```nix
../../modules/home/alacritty/apps.nix
```
To:
```nix
../../modules/home/ghostty/apps.nix
```

**Step 2: Update GNOME favorite apps**

In `dconf.settings` `"org/gnome/shell"` (line 91-101), change:

```nix
"Alacritty.desktop"
```
to:
```nix
"com.mitchellh.ghostty.desktop"
```

**Step 3: Update auto-move-windows**

In `"org/gnome/shell/extensions/auto-move-windows"` (line 126-137), change:

```nix
"Alacritty.desktop:2"
```
to:
```nix
"com.mitchellh.ghostty.desktop:2"
```

**Step 4: Switch app entries from alacrittyApps to ghosttyApps**

Change `alacrittyApps.apps` (line 162) to `ghosttyApps.apps`:

```nix
ghosttyApps.apps = [
  {
    name = "btop";
    command = "btop";
    categories = [ "System" ];
    icon = ../../icons/btop.png;
  }
];
```

**Step 5: Commit**

```bash
git add users/jordangarrison/home-linux.nix
git commit -m "feat(ghostty): switch GNOME and desktop entries to ghostty"
```

---

### Task 6: Update Niri Keybindings to Use Ghostty

**Files:**
- Modify: `modules/home/niri/default.nix:374` (Mod+Return)
- Modify: `modules/home/niri/default.nix:387-391` (Mod+F yazi)
- Modify: `modules/home/niri/default.nix:409-418` (Mod+Shift+D dictation)

**Step 1: Update terminal launcher**

Change line 374:
```nix
"Mod+Return".action.spawn = "alacritty";
```
to:
```nix
"Mod+Return".action.spawn = "ghostty";
```

**Step 2: Update yazi file manager launcher**

Change lines 387-391:
```nix
"Mod+F".action.spawn = [
  "alacritty"
  "-e"
  "yazi"
];
```
to:
```nix
"Mod+F".action.spawn = [
  "ghostty"
  "-e"
  "yazi"
];
```

**Step 3: Update Sweet Nothings dictation launcher**

Change lines 409-418:
```nix
"Mod+Shift+D".action.spawn = [
  "alacritty"
  "--class"
  "sweet-nothings"
  "--title"
  "Sweet Nothings"
  "-e"
  "sweet-nothings"
  "--paste"
];
```
to:
```nix
"Mod+Shift+D".action.spawn = [
  "ghostty"
  "--class=sweet-nothings"
  "--title=Sweet Nothings"
  "-e"
  "sweet-nothings"
  "--paste"
];
```

Note: Ghostty uses `--flag=value` syntax (not `--flag value` with separate args for `--class` and `--title`).

**Step 4: Commit**

```bash
git add modules/home/niri/default.nix
git commit -m "feat(ghostty): update niri keybindings to use ghostty"
```

---

### Task 7: Update Hyprland Keybindings to Use Ghostty

**Files:**
- Modify: `users/jordangarrison/configs/hypr/keybinds.conf:7` ($terminal)
- Modify: `users/jordangarrison/configs/hypr/keybinds.conf:11` ($terminalFileManager)

**Step 1: Change terminal variable**

Change line 7:
```conf
$terminal = wezterm
```
to:
```conf
$terminal = ghostty
```

**Step 2: Change terminal file manager**

Change line 11:
```conf
$terminalFileManager = wezterm start -- yazi
```
to:
```conf
$terminalFileManager = ghostty -e yazi
```

**Step 3: Commit**

```bash
git add users/jordangarrison/configs/hypr/keybinds.conf
git commit -m "feat(ghostty): update hyprland keybindings to use ghostty"
```

---

### Task 8: Build and Verify

**Step 1: Build the NixOS configuration (without switching)**

Run: `nh os build .`
Expected: Successful build with no errors

**Step 2: Verify ghostty binary exists in the build**

Run: `nix build .#nixosConfigurations.endeavour.config.system.build.toplevel --dry-run 2>&1 | head -20`
Expected: No evaluation errors

**Step 3: Commit any fixups if needed**

If build fails, fix issues and commit with appropriate message.

---

### Task 9: Update Niri CLAUDE.md Keybindings Reference

**Files:**
- Modify: `modules/home/niri/CLAUDE.md`

**Step 1: Update keybinding references**

In the keybindings table, change:
- `Mod+Return` → `Ghostty terminal` (was `Alacritty terminal`)
- `Mod+F` → `Yazi file manager (in Ghostty)` (was `in terminal`)
- `Mod+Shift+D` → reference Ghostty instead of Alacritty

**Step 2: Commit**

```bash
git add modules/home/niri/CLAUDE.md
git commit -m "docs(niri): update keybinding docs for ghostty"
```
