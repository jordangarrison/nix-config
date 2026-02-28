# Fix Ghostty Tabs on macOS — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix Ghostty tab creation on macOS by making the config platform-aware using the dendritic Conditional Aspect pattern.

**Architecture:** Create a Home Manager module at `modules/home/ghostty/default.nix` that uses `lib.mkMerge` + `lib.mkIf` to generate platform-specific Ghostty config. Darwin class gets `window-decoration = auto` + `macos-titlebar-style = tabs`; NixOS class keeps `window-decoration = none` + `gtk-titlebar = false`. Common settings (font, theme, opacity, keybinds) are shared.

**Tech Stack:** Nix, Home Manager, Ghostty

---

### Task 1: Create the Ghostty config module

**Files:**
- Create: `modules/home/ghostty/default.nix`

**Step 1: Create the module**

```nix
{ pkgs, lib, ... }:

let
  commonConfig = ''
    # Font
    font-family = Source Code Pro
    font-size = 10

    # Window
    background-opacity = 0.80
    window-padding-x = 5
    window-padding-y = 5

    # Theme (built-in rose-pine)
    theme = Rose Pine

    # Shell integration
    shell-integration = zsh

    # Keybindings
    # Shift+Enter sends newline for Claude Code multiline input
    keybind = shift+enter=text:\n
  '';
in
lib.mkMerge [
  {
    # Common config for all platforms
    home.file.".config/ghostty/config".text = commonConfig;
  }
  (lib.mkIf pkgs.stdenv.isLinux {
    # NixOS class: tiling WM manages decorations
    home.file.".config/ghostty/config".text = lib.mkForce (commonConfig + ''

      # Linux/NixOS: tiling WM manages decorations
      window-decoration = none
      gtk-titlebar = false
    '');
  })
  (lib.mkIf pkgs.stdenv.isDarwin {
    # Darwin class: native tab bar
    home.file.".config/ghostty/config".text = lib.mkForce (commonConfig + ''

      # macOS/Darwin: native tab bar
      window-decoration = auto
      macos-titlebar-style = tabs
    '');
  })
]
```

**Step 2: Verify syntax**

Run: `nix-instantiate --parse modules/home/ghostty/default.nix`
Expected: Parsed output with no errors.

---

### Task 2: Wire up the module and remove the static config

**Files:**
- Modify: `users/jordangarrison/home.nix:702` — remove static symlink
- Modify: `users/jordangarrison/home.nix` (imports section) — add module import
- Delete: `users/jordangarrison/tools/ghostty/config`

**Step 1: Add the module import to home.nix**

In `users/jordangarrison/home.nix`, the file does not have a top-level `imports` list. The ghostty config is managed via `home.file`. We need to add an `imports` for the new module.

Check: `home.nix` currently has no `imports = [ ... ];` block at the top level. However, it is imported by `home-linux.nix` and `home-darwin.nix` which do have imports. The cleanest approach is to add the ghostty module import to both `home-linux.nix` and `home-darwin.nix` so it's available on both platforms.

**In `users/jordangarrison/home-linux.nix`**, add to imports:
```nix
imports = [
  ./home.nix
  ../../modules/home/brave/apps.nix
  ../../modules/home/ghostty           # <-- add this
  ../../modules/home/ghostty/apps.nix
  ../../modules/home/wezterm
  ../../modules/home/virt-manager/config.nix
  ../../modules/home/languages
  ../../modules/home/zed-editor
];
```

**In `users/jordangarrison/home-darwin.nix`**, add to imports:
```nix
imports = [
  ./home.nix
  ../../modules/home/ghostty  # <-- add this
];
```

**Step 2: Remove the static symlink from home.nix**

Remove line 701-702:
```nix
    # Ghostty terminal configuration
    ".config/ghostty/config".source = ./tools/ghostty/config;
```

**Step 3: Delete the old static config**

Run: `rm users/jordangarrison/tools/ghostty/config`

**Step 4: Verify flake evaluates**

Run: `nix flake check --no-build 2>&1 | head -20`
Expected: No evaluation errors.

---

### Task 3: Build and verify

**Step 1: Build darwin config**

Run: `nh darwin build .`
Expected: Builds successfully.

**Step 2: Inspect generated config**

Run: `cat $(nix eval --raw .#darwinConfigurations.H952L3DPHH.config.home-manager.users.\"jordan.garrison\".home.file.\".config/ghostty/config\".text 2>/dev/null || echo "check manually after switch")`

Alternatively after switching, check `~/.config/ghostty/config` contains:
- `window-decoration = auto`
- `macos-titlebar-style = tabs`
- Does NOT contain `gtk-titlebar = false`

**Step 3: Verify tabs work**

After `nh darwin switch .`, open Ghostty and press Cmd+T. A new tab should open.

---

### Task 4: Commit

**Step 1: Stage and commit**

```bash
git add modules/home/ghostty/default.nix
git add users/jordangarrison/home.nix
git add users/jordangarrison/home-linux.nix
git add users/jordangarrison/home-darwin.nix
git rm users/jordangarrison/tools/ghostty/config
git commit -m "fix: make ghostty config platform-aware for macOS tabs

Use dendritic Conditional Aspect pattern to branch Ghostty config
by platform class. Darwin gets window-decoration=auto with native
tab bar; NixOS keeps window-decoration=none for tiling WMs."
```
