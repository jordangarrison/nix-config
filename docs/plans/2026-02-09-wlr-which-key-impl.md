# wlr-which-key Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add wlr-which-key as an interactive hierarchical command menu for the Niri compositor, triggered by `Mod+D`.

**Architecture:** Create a Home Manager module at `modules/home/wlr-which-key/default.nix` that declaratively generates a YAML config using `pkgs.writeText` and wraps it with `pkgs.writeShellScriptBin`. The module is imported from the niri home module. New screenshot scripts handle focused-monitor and window capture workflows.

**Tech Stack:** Nix (Home Manager module), wlr-which-key (nixpkgs), grim/slurp/satty (screenshots), wpctl (audio), niri msg (compositor IPC)

**Design doc:** `docs/plans/2026-02-09-wlr-which-key-design.md`

---

### Task 1: Create new screenshot scripts

Three new scripts are needed for focused-monitor and window screenshot workflows that don't exist yet.

**Files:**
- Create: `users/jordangarrison/configs/hypr/scripts/screenshot-focused-monitor-satty.sh`
- Create: `users/jordangarrison/configs/hypr/scripts/screenshot-window-satty.sh`
- Create: `users/jordangarrison/configs/hypr/scripts/screenshot-focused-monitor-clipboard.sh`

**Step 1: Create screenshot-focused-monitor-satty.sh**

```bash
#!/usr/bin/env bash
# Focused monitor screenshot with Satty annotation
# Uses niri msg to get focused output, then grim to capture just that output
FOCUSED=$(niri msg -j focused-output | jq -r '.name')
grim -o "$FOCUSED" -t ppm - | satty --filename - --output-filename ~/Pictures/Screenshots/$(date '+%Y%m%d-%H%M%S').png
```

**Step 2: Create screenshot-window-satty.sh**

```bash
#!/usr/bin/env bash
# Active window screenshot with Satty annotation
# Uses niri msg to get focused window geometry, then grim to capture that region
WINDOW=$(niri msg -j focused-window | jq -r '"\(.x),\(.y) \(.width)x\(.height)"')
grim -g "$WINDOW" -t ppm - | satty --filename - --output-filename ~/Pictures/Screenshots/$(date '+%Y%m%d-%H%M%S').png
```

**Step 3: Create screenshot-focused-monitor-clipboard.sh**

```bash
#!/usr/bin/env bash
# Focused monitor screenshot to clipboard
FOCUSED=$(niri msg -j focused-output | jq -r '.name')
grim -o "$FOCUSED" - | wl-copy
```

**Step 4: Make all three scripts executable**

Run: `chmod +x users/jordangarrison/configs/hypr/scripts/screenshot-focused-monitor-satty.sh users/jordangarrison/configs/hypr/scripts/screenshot-window-satty.sh users/jordangarrison/configs/hypr/scripts/screenshot-focused-monitor-clipboard.sh`

**Step 5: Commit**

```bash
git add users/jordangarrison/configs/hypr/scripts/screenshot-focused-monitor-satty.sh users/jordangarrison/configs/hypr/scripts/screenshot-window-satty.sh users/jordangarrison/configs/hypr/scripts/screenshot-focused-monitor-clipboard.sh
git commit -m "feat: add focused-monitor and window screenshot scripts"
```

---

### Task 2: Create the wlr-which-key Home Manager module

This is the core module that generates the YAML config and wrapper script.

**Files:**
- Create: `modules/home/wlr-which-key/default.nix`

**Step 1: Create the module directory**

Run: `mkdir -p modules/home/wlr-which-key`

**Step 2: Write the module**

Create `modules/home/wlr-which-key/default.nix`. This module:
- Installs `pkgs.wlr-which-key`
- Generates a YAML config file via `pkgs.writeText` using `lib.generators.toYAML`
- Creates a wrapper script `wlr-which-key-menu` via `pkgs.writeShellScriptBin`
- Includes the full menu tree from the design doc

The `scriptsPath` variable must match how the niri module defines it: `${homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/configs/hypr/scripts`.

```nix
{ config, pkgs, lib, ... }:

let
  homeDirectory = config.home.homeDirectory;
  scriptsPath = "${homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/configs/hypr/scripts";

  # Helper to create a menu entry
  entry = key: desc: cmd: { inherit key desc cmd; };
  submenu = key: desc: items: { inherit key desc; submenu = items; };

  menuConfig = {
    # Theming
    font = "JetBrainsMono Nerd Font 12";
    background = "#282828d0";
    color = "#fbf1c7";
    border = "#8ec07c";
    separator = " -> ";
    border_width = 2;
    corner_r = 10;
    padding = 15;
    anchor = "center";

    menu = [
      # [p] Power
      (submenu "p" "Power" [
        (entry "s" "Suspend" "systemctl suspend")
        (entry "r" "Reboot" "systemctl reboot")
        (entry "o" "Shutdown" "systemctl poweroff")
        (entry "l" "Lock Screen" "noctalia-shell ipc call lockScreen lock")
      ])

      # [s] Screenshots
      (submenu "s" "Screenshots" [
        (entry "r" "Region -> Annotate" "${scriptsPath}/screenshot-region-satty.sh")
        (entry "s" "Screen -> Annotate" "${scriptsPath}/screenshot-focused-monitor-satty.sh")
        (entry "w" "Window -> Annotate" "${scriptsPath}/screenshot-window-satty.sh")
        (entry "c" "Region -> Clipboard" "${scriptsPath}/screenshot-region-clipboard.sh")
        (entry "f" "Screen -> Clipboard" "${scriptsPath}/screenshot-focused-monitor-clipboard.sh")
        (entry "a" "All Monitors -> Annotate" "${scriptsPath}/screenshot-full-satty.sh")
        (entry "A" "All Monitors -> Clipboard" "${scriptsPath}/screenshot-full-clipboard.sh")
      ])

      # [a] Apps
      (submenu "a" "Apps" [
        (submenu "a" "AI Tools" [
          (entry "c" "Claude" "brave --app=https://claude.ai")
          (entry "g" "ChatGPT" "brave --app=https://chat.openai.com")
          (entry "m" "Gemini" "brave --app=https://gemini.google.com")
        ])
        (submenu "s" "System" [
          (entry "b" "btop" "alacritty -e btop")
          (entry "n" "Network" "alacritty -e nmtui")
        ])
        (submenu "m" "Media" [
          (entry "o" "OBS Studio" "obs")
        ])
      ])

      # [w] Web
      (submenu "w" "Web" [
        (submenu "m" "Mail" [
          (entry "p" "Personal Gmail" "brave https://mail.google.com/mail/u/0/#inbox")
          (entry "w" "Work Gmail" "brave https://mail.google.com/mail/u/1/#inbox")
          (entry "f" "Family Gmail" "brave https://mail.google.com/mail/u/2/#inbox")
          (entry "i" "iCloud Mail" "brave https://icloud.com/mail")
        ])
        (submenu "g" "GitHub" [
          (submenu "p" "Personal" [
            (entry "p" "Profile" "brave https://github.com/jordangarrison")
            (entry "n" "Nix Config" "brave https://github.com/jordangarrison/nix-config")
          ])
          (submenu "f" "Flocasts" [
            (entry "o" "Org" "brave https://github.com/flocasts")
            (entry "i" "Infra Base Services" "brave https://github.com/flocasts/infra-base-services")
            (entry "w" "Web Monorepo" "brave https://github.com/flocasts/web-monorepo")
            (entry "t" "Teams" "brave https://github.com/orgs/flocasts/teams")
          ])
          (submenu "e" "Enterprise" [
            (entry "d" "Dashboard" "brave https://github.com/enterprises/flosports/")
            (entry "p" "People" "brave https://github.com/enterprises/flosports/people")
            (entry "a" "AI Controls" "brave https://github.com/enterprises/flosports/ai-controls/agents")
          ])
        ])
        (entry "j" "Jira Board" "brave https://flocasts.atlassian.net/jira/software/c/projects/INFRA/boards/166")
        (entry "c" "Calendar" "brave https://calendar.google.com/calendar/u/1/r/week")
        (entry "t" "Meet" "brave --app=https://meet.google.com")
      ])

      # [m] Media
      (submenu "m" "Media" [
        (entry "h" "Headphones" "pactl set-default-sink $(pactl list short sinks | grep -i headphone | head -1 | cut -f2)")
        (entry "s" "Speakers" "pactl set-default-sink $(pactl list short sinks | grep -iv headphone | grep -iv monitor | head -1 | cut -f2)")
        (entry "m" "Toggle Mic Mute" "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")
      ])

      # [x] Session
      (submenu "x" "Session" [
        (entry "r" "Reload Config" "niri msg action reload-config")
        (entry "q" "Quit Niri" "niri msg action quit")
        (entry "h" "Hotkey Overlay" "niri msg action show-hotkey-overlay")
      ])

      # [d] Display
      (submenu "d" "Display" [
        (entry "h" "Focus Monitor Left" "niri msg action focus-monitor-left")
        (entry "l" "Focus Monitor Right" "niri msg action focus-monitor-right")
        (entry "H" "Move to Monitor Left" "niri msg action move-window-to-monitor-left")
        (entry "L" "Move to Monitor Right" "niri msg action move-window-to-monitor-right")
      ])
    ];
  };

  configFile = pkgs.writeText "wlr-which-key-config.yaml" (builtins.toJSON menuConfig);

  whichKeyMenu = pkgs.writeShellScriptBin "wlr-which-key-menu" ''
    exec ${pkgs.wlr-which-key}/bin/wlr-which-key ${configFile}
  '';
in
{
  home.packages = [
    pkgs.wlr-which-key
    whichKeyMenu
  ];
}
```

**Note:** `builtins.toJSON` produces valid YAML (JSON is a subset of YAML). wlr-which-key accepts YAML config files, and JSON is valid YAML. This avoids needing a separate YAML generator.

**Note:** The audio switching commands use `pactl` with grep to find sink names dynamically. This is a placeholder — the user may need to adjust the grep patterns to match their actual sink names after testing on their hardware.

**Step 3: Commit**

```bash
git add modules/home/wlr-which-key/default.nix
git commit -m "feat: add wlr-which-key home manager module with full menu config"
```

---

### Task 3: Import the module from the niri config

The wlr-which-key module needs to be imported into the niri home module so it's available on all hosts running niri.

**Files:**
- Modify: `modules/home/niri/default.nix:49-50` (imports section)

**Step 1: Add the import**

In `modules/home/niri/default.nix`, the imports are at line 50:

```nix
  imports = [ ../desktop-tools ];
```

Change to:

```nix
  imports = [
    ../desktop-tools
    ../wlr-which-key
  ];
```

**Step 2: Commit**

```bash
git add modules/home/niri/default.nix
git commit -m "feat: import wlr-which-key module into niri config"
```

---

### Task 4: Add the Mod+D keybinding and remove old screenshot binds

Wire up the which-key menu trigger and remove the screenshot keybinds that are now in the menu.

**Files:**
- Modify: `modules/home/niri/default.nix:355-643` (binds section)

**Step 1: Add Mod+D binding**

After the program launchers section (around line 391, after the Sweet Nothings binding), add:

```nix
      # Which-key menu (D for discover)
      "Mod+D".action.spawn = "wlr-which-key-menu";
```

**Step 2: Remove old screenshot keybinds**

Remove these lines from the binds section (lines 502-525):

```nix
      # Region select with Satty annotation
      "Mod+Alt+S".action.spawn = [ ... ];
      # Full screen with Satty annotation
      "Mod+Alt+A".action.spawn = [ ... ];
      # Quick region to clipboard
      "Mod+Alt+C".action.spawn = [ ... ];
      # Full screen to clipboard
      "Mod+Alt+F".action.spawn = [ ... ];
```

Keep the niri built-in screenshot binds (`Print` and `Shift+Print`).

**Step 3: Commit**

```bash
git add modules/home/niri/default.nix
git commit -m "feat: add Mod+D which-key binding, remove Mod+Alt screenshot binds"
```

---

### Task 5: Build and verify

Test that the configuration builds without errors.

**Files:** None (verification only)

**Step 1: Build the NixOS configuration**

Run: `nh os build /home/jordangarrison/dev/jordangarrison/nix-config`

Expected: Build succeeds without errors. If it fails, check:
- YAML/JSON generation issues in the module
- Missing package references
- Import path errors

**Step 2: Inspect the generated config**

Run: `cat $(nix build /home/jordangarrison/dev/jordangarrison/nix-config#nixosConfigurations.endeavour.config.home-manager.users.jordangarrison.home.packages --no-link --print-out-paths 2>/dev/null | head -1)/bin/wlr-which-key-menu 2>/dev/null || echo "Check build output manually"`

Alternatively, after a successful build, inspect the wrapper script to verify paths are correct.

**Step 3: Commit (if any fixes were needed)**

```bash
git add -A
git commit -m "fix: resolve build issues with wlr-which-key module"
```

---

### Task 6: Update documentation

Update the niri keybinds help script and CLAUDE.md to reflect the new menu.

**Files:**
- Modify: `users/jordangarrison/configs/hypr/scripts/niri-keybinds-help.sh`
- Modify: `modules/home/niri/CLAUDE.md`

**Step 1: Update niri-keybinds-help.sh**

Replace the `[SCREENSHOTS]` section to note they moved to the which-key menu. Add a `[WHICH-KEY MENU]` section:

In the `show_keybinds()` function, replace the screenshots section and add the which-key section:

```
[WHICH-KEY MENU (Mod+D)]
p                         → Power (suspend/reboot/shutdown/lock)
s                         → Screenshots (region/screen/window + annotate/clipboard)
a                         → Apps (AI tools, system tools, media)
w                         → Web (mail, GitHub, Jira, Calendar, Meet)
m                         → Media (headphones/speakers/mic mute)
x                         → Session (reload config, quit, hotkey overlay)
d                         → Display (monitor focus/move, scale)

[SCREENSHOTS (via Mod+D → s)]
s then r                  → Region select + Satty annotation
s then s                  → Focused screen + Satty annotation
s then w                  → Window + Satty annotation
s then c                  → Region to clipboard
s then f                  → Focused screen to clipboard
s then a                  → All monitors + Satty annotation
s then A                  → All monitors to clipboard
```

Remove the old `[SCREENSHOTS]` section with the `Super + Alt` bindings.

**Step 2: Update CLAUDE.md**

In `modules/home/niri/CLAUDE.md`, add a section about wlr-which-key under the "Keybindings" section. Update the screenshots section to note they're now in the which-key menu.

**Step 3: Commit**

```bash
git add users/jordangarrison/configs/hypr/scripts/niri-keybinds-help.sh modules/home/niri/CLAUDE.md
git commit -m "docs: update keybind help and CLAUDE.md for wlr-which-key"
```

---

## Post-Implementation Notes

**Testing on hardware:**
- After `nh os switch`, press `Mod+D` to open the menu
- Verify each submenu navigates correctly
- Test screenshot scripts (focused monitor, window) to confirm `niri msg -j` output format
- Test audio switching — may need to adjust grep patterns in the Media submenu commands to match actual sink names from `pactl list short sinks`

**Open items for later:**
- Host-specific display scale submenu (needs per-host monitor names/resolutions)
- Fine-tune audio sink names after testing on hardware
- Decide whether to remove redundant direct keybinds (`Mod+Ctrl+Alt+L`, `Mod+Shift+C`, `Mod+Shift+Q`)
- Decide whether to remove `Mod+/` keybinds-help.sh
