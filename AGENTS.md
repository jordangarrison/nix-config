# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, WARP, etc.) when working with code in this repository.

## Repository Overview

This is Jordan Garrison's personal Nix configuration repository, providing declarative system configurations for multiple platforms and users using Nix Flakes. The repository supports NixOS, macOS (via nix-darwin), and WSL/Ubuntu (via Home Manager).

## Essential Commands

### System Management

```bash
# NixOS systems (using nh)
# build first
nh os build .

# test next
nh os test .

# finally switch if and only if build and test pass
nh os switch .

# macOS systems (nix-darwin)
nh darwin switch .

# Home Manager only (WSL/Ubuntu)
nh home switch .

# Development shell (for bootstrapping)
nix develop #or you can rely on direnv

# Traditional commands (if nh is not available)
# sudo nixos-rebuild switch --flake .#<hostname>
# sudo darwin-rebuild switch --flake .#<hostname>
# home-manager switch --flake .#<config>
```

### Package and Flake Management

```bash
# Update all flake inputs
nh flake update

# Check flake configuration
nh flake check

# Show flake information
nh flake show

# Clean up old generations
nh clean all

# Traditional commands (if needed)
# nix flake update
# nix flake check
# nix flake show
```

#### Searching for packages

Leverage the nix mcp to look up packages and all their versions

### Git Commands (configured for --no-pager)

All git commands in this repository are configured to disable pager output by default. This is enforced through user rules in the shell environment.

## Available Configurations

### NixOS Hosts

- **endeavour**: Main desktop workstation (MSI B550-A Pro, AMD GPU)
  - Full desktop environment (GNOME + Hyprland + Niri)
  - Gaming setup (Steam)
  - Development tools
  - Remote desktop enabled

- **opportunity**: Framework 12 laptop (13th Gen Intel)
  - Desktop environments (GNOME + Hyprland + Niri)
  - Tablet mode enabled (touchscreen gestures, auto-rotation, OSK)
  - Development tools
  - Virtualization enabled

- **voyager**: MacBook Pro running NixOS (Apple hardware profile)
  - Laptop-optimized GNOME configuration
  - Development environment

- **discovery**: AMD-based system
  - Minimal GNOME setup
  - Standard development tools

### Darwin Configuration

- **H952L3DPHH**: Work MacBook (nix-darwin)
  - Home Manager integration for user environment
  - Work-specific tooling

### Home Manager Configuration

- **jordangarrison@normandy**: WSL/Ubuntu standalone setup
  - Pure Home Manager without system management
  - Development tools and user environment only

## Architecture Overview

### Flake-Based Multi-Platform Design

The `flake.nix` serves as the central orchestrator for all configurations:

**Inputs:**

- `nixpkgs`: Main package repository (nixos-unstable)
- `nixos-hardware`: Hardware-specific configurations
- `nix-darwin`: macOS system management
- `home-manager`: User environment management
- `nvf`: Highly modular Neovim configuration framework
- `niri`: Scrollable-tiling Wayland compositor
- `noctalia`: Unified desktop shell (bar, notifications, launcher, lock screen)
- Custom flakes: `aws-tools`, `aws-use-sso`, `hubctl` (Jordan's tools)

**Outputs:**

- `nixosConfigurations`: Full NixOS system configurations
- `darwinConfigurations`: macOS system configurations
- `homeConfigurations`: Standalone Home Manager configurations

### Host and User Management Pattern

Each system configuration follows a consistent pattern:

1. **Host-specific configuration** (`hosts/<name>/configuration.nix`)
2. **Hardware configuration** (`hosts/<name>/hardware-configuration.nix`)
3. **Shared modules** (from `modules/nixos/`)
4. **User configurations** (from `users/<name>/nixos.nix`)
5. **Home Manager integration** with platform-specific home configs

## Directory Structure

```
├── flake.nix                 # Central flake configuration
├── hosts/                    # Host-specific configurations
│   ├── endeavour/           # Desktop workstation (NixOS)
│   ├── voyager/             # MacBook Pro (NixOS)
│   ├── discovery/           # AMD system (NixOS)
│   └── flomac/              # Work MacBook (nix-darwin)
├── users/                   # User configurations
│   ├── jordangarrison/      # Primary user
│   │   ├── nixos.nix        # NixOS user module
│   │   ├── home.nix         # Core Home Manager config
│   │   ├── home-linux.nix   # Linux-specific Home Manager
│   │   ├── home-darwin.nix  # macOS-specific Home Manager
│   │   ├── configs/         # Application configurations
│   │   └── tools/           # Custom scripts and tools
│   │     └── doom.d/        # Emacs Doom configuration
│   ├── mikayla/            # Family member configurations
│   ├── jane/               # (Similar structure for each user)
│   └── isla/
├── modules/
│   ├── nixos/              # Shared NixOS modules
│   │   ├── common.nix      # Base system configuration
│   │   ├── gnome-desktop.nix
│   │   ├── hyprland-desktop.nix
│   │   ├── niri-desktop.nix # Niri compositor (system-level)
│   │   ├── development.nix # Docker, Emacs, dev tools
│   │   └── fonts.nix
│   └── home/               # Home Manager modules
│       ├── niri/           # Niri configuration (Home Manager)
│       ├── brave/apps.nix  # Brave browser app integration
│       └── alacritty/apps.nix # Terminal app shortcuts
└── shell.nix              # Development shell
```

## User Configuration System

### User Module Pattern

Each user has:

- `nixos.nix`: Defines system-level user account, groups, and system packages
- `home.nix`: Core Home Manager configuration (cross-platform)
- `home-linux.nix`: Linux-specific Home Manager settings
- `home-darwin.nix`: macOS-specific Home Manager settings

### Multi-User Family Setup

The configuration supports multiple family members (jordangarrison, mikayla, jane, isla) with:

- Individual user modules in `users/<name>/nixos.nix`
- Shared system modules from `modules/nixos/`
- Per-host user enablement in `flake.nix`

### Platform-Specific Features

**Linux (GNOME)**:

- 10 fixed workspaces with Super+number shortcuts
- Application-to-workspace assignments via auto-move-windows extension
- GNOME extensions: AppIndicator, Clipboard History, Fuzzy App Search, GSConnect
- Brave browser with extensions and custom web apps
- Alacritty terminal integration

**macOS (Darwin)**:

- Homebrew integration
- macOS-specific application paths
- Work environment optimizations

## Common Development Tasks

### Adding New Packages

**System packages** (affects all users):

```nix
# In modules/nixos/common.nix
environment.systemPackages = with pkgs; [
  new-package
];
```

**User packages** (specific to Jordan):

```nix
# In users/jordangarrison/home.nix
home.packages = with pkgs; [
  new-package
];
```

### Updating the System

1. Update flake inputs: `nh flake update`
2. Review changes: `git diff flake.lock`
3. Rebuild system with appropriate command for your platform:
   - NixOS:
     - `nh os build .`
     - `nh os test .`
     - `nh os switch .`
   - macOS:
     - `nh darwin build .`
     - `nh darwin switch .`
   - Home Manager: `nh home switch .`
4. Commit updates: `git add flake.lock && git commit -m "Update flake inputs"`

### Development Environment

The repository includes a development shell (`shell.nix`) with:

- Git, Home Manager, Neovim, Nix with flakes enabled
- Use `nix develop` to enter this environment

### Managing Custom Tools

Custom tools are integrated via flake inputs:

- `aws-tools`: AWS utilities
- `aws-use-sso`: AWS SSO helper
- `hubctl`: Container management utility

These are included in the home.nix packages and automatically built from their respective repositories.

### Initial Setup (Non-NixOS Systems)

For macOS or other non-NixOS systems, install Nix first using the Determinate Systems installer:

```bash
./install-determinant-systems-nix.sh
```

## Platform-Specific Notes

### NixOS Systems

- AppImage support is enabled system-wide
- Flatpak integration available
- Tailscale networking configured
- Docker enabled for development
- 1Password GUI with policy ownership for Jordan

### GNOME Configuration

- Workspaces 1-10 mapped to Super+1-0
- Super+Shift+number moves windows to workspaces
- Application shortcuts: Super+B (Brave), Super+W (WezTerm), Super+C (Cursor), etc.
- Auto-move-windows extension places applications on specific workspaces

### Hyprland Configuration

- Wallpapers managed via hyprpaper
- Wallpaper files stored in `users/jordangarrison/wallpapers/`
- Monitor configurations:
  - endeavour (desktop): DP-3, DP-4
  - opportunity (laptop): eDP-1

**Set Wallpaper:**

```bash
# Apply wallpaper immediately
./users/jordangarrison/configs/hypr/scripts/set-wallpaper.sh /path/to/wallpaper.jpg
```

**Configuration Files:**

- `users/jordangarrison/configs/hypr/hyprpaper.conf`: Wallpaper daemon config
- `users/jordangarrison/configs/hypr/autostart.conf`: Startup commands including wallpaper

### Niri Configuration

Niri is a scrollable-tiling Wayland compositor. Configuration is fully declarative via `programs.niri.settings`.

**Key Features:**

- Scrollable tiling: windows tile in columns that scroll horizontally
- Build-time config validation (errors caught during `nh os build`)
- Noctalia shell: unified bar, notifications, launcher, lock screen
- Keybindings similar to Hyprland (Mod+H/J/K/L for navigation)

**Shell Components (noctalia-shell):**

- Status bar (replaces waybar)
- Notifications (replaces mako)
- Application launcher: `Mod+Space`
- Lock screen: `Mod+Ctrl+Alt+L`

**Monitor Setup (endeavour):**

- DP-3: 3840x2160 @ 60Hz, scale 1.5 (primary, workspaces 1-10)
- DP-4: 2560x1440 @ 165Hz, portrait (dynamic workspaces)

**Configuration Files:**

- `modules/nixos/niri-desktop.nix`: System-level niri setup
- `modules/home/niri/default.nix`: Full declarative config (keybindings, layout, animations)
- `modules/home/niri/CLAUDE.md`: Detailed keybinding reference and troubleshooting

**Resources:**

- [niri GitHub](https://github.com/YaLTeR/niri)
- [niri-flake](https://github.com/sodiboo/niri-flake)
- [noctalia-shell](https://github.com/noctalia-dev/noctalia-shell)

### Tablet Mode Configuration

Tablet mode provides touchscreen gesture support, auto-rotation, and on-screen keyboard for touchscreen devices (currently enabled on **opportunity** - Framework 12 laptop).

**System Requirements:**

- User must be in the `input` group for touchscreen access
- Hardware sensor support (`hardware.sensor.iio.enable`) for auto-rotation
- Touchscreen device with stable `/dev/input/by-path/` identifier

**Components:**

1. **lisgd** - Touchscreen gesture daemon
   - Detects multi-finger swipe gestures on touchscreen
   - Configured via systemd user service
   - Device path: `/dev/input/by-path/pci-0000:00:15.0-platform-i2c_designware.0-event`

2. **iio-niri** - Auto-rotation daemon
   - Monitors accelerometer via iio-sensor-proxy
   - Automatically rotates display based on device orientation
   - Integrated with niri compositor

3. **wvkbd** - Wayland virtual keyboard
   - On-screen keyboard for touch input
   - Shows/hides on gesture or can be started manually

**Touch Gestures:**

| Gesture                               | Action                                 |
| ------------------------------------- | -------------------------------------- |
| 3-finger swipe left                   | Switch to previous workspace           |
| 3-finger swipe right                  | Switch to next workspace               |
| 3-finger swipe up from bottom         | Toggle application launcher            |
| 3-finger swipe down from top          | Close current window                   |
| 1-finger swipe up from bottom (short) | Show on-screen keyboard                |
| 2-finger swipe down from top          | Hide on-screen keyboard                |
| 2-finger swipe left                   | Browser back navigation (Alt+Left)     |
| 2-finger swipe right                  | Browser forward navigation (Alt+Right) |

**Configuration Files:**

- `modules/nixos/tablet-mode.nix`: System-level tablet mode module (hardware sensor support)
- `modules/home/tablet-mode/default.nix`: Gesture definitions and user services
- `users/jordangarrison/nixos.nix`: User must have `"input"` in extraGroups

**Enabling Tablet Mode:**

In `flake.nix` for a specific host:

```nix
{
  # System-level: import tablet-mode module
  imports = [
    ./modules/nixos/tablet-mode.nix
  ];

  # Enable tablet mode
  tablet-mode.enable = true;

  # Home Manager: import tablet-mode home module
  home-manager.users.jordangarrison.imports = [
    ./modules/home/tablet-mode
  ];
}
```

Ensure user has input group access in `users/<username>/nixos.nix`:

```nix
extraGroups = [ "networkmanager" "wheel" "docker" "input" ];
```

**Troubleshooting:**

Check service status:

```bash
systemctl --user status lisgd
systemctl --user status iio-niri
journalctl --user -u lisgd -f
```

Verify permissions:

```bash
groups  # Should include 'input'
ls -la /dev/input/event*  # Should show group 'input'
```

Find touchscreen device:

```bash
for dev in /dev/input/event*; do
  name=$(cat /sys/class/input/$(basename $dev)/device/name 2>/dev/null || echo "unknown")
  echo "$dev: $name"
done
```

**Known Issues:**

- Group membership changes require logout/login to take effect
- Device path may vary on different hardware; update `modules/home/tablet-mode/default.nix` if needed
- Gestures from bottom edge may not work when OSK is visible (use top-edge gestures instead)

### Development Tools

- **Emacs with Doom configuration**: Primary editor with literate configuration
  - Located in `users/jordangarrison/tools/doom.d/`
  - Literate configuration in `config.org`
  - Includes NixOS integration, AI/LLM tools, and extensive development features
  - Custom key bindings and workflow optimizations
- **Neovim with nvf**: Secondary editor with minimal, declarative configuration
  - Managed via `programs.nvf` in Home Manager
  - LSP support enabled by default
  - See `users/jordangarrison/tools/nvim/README.md` for details
- VSCode (via code-cursor package)
- Multiple language servers and runtimes (Go, Node.js, Python, Ruby, Rust)
- Terraform, Kubernetes, AWS tooling
- Git with diff-so-fancy integration

## Maintenance and Troubleshooting

### Automated Updates

- GitHub Actions workflow updates `flake.lock` daily
- Creates pull requests with dependency updates
- Review and merge PR to apply updates system-wide

### SSH Configuration

- SSH config managed via Home Manager with proper permissions
- Configuration applied via onChange hook to fix symlink permissions

### Custom Scripts

- Located in `users/jordangarrison/tools/scripts/`
- Integrated into PATH via Home Manager
- Include utilities for AWS, tmux, wallpapers, IP checking

### Git Configuration

- All git commands configured with `--no-pager` flag
- Diff display enhanced with diff-so-fancy
- Aliases for common operations (gss, pu, gd, gdca)

### Emacs Doom Configuration

**Primary Editor**: Emacs with Doom framework, featuring a comprehensive literate configuration.

**Key Features:**

- Literate configuration in `users/jordangarrison/tools/doom.d/config.org`
- NixOS system integration with `nh` command runners
- AI/LLM integration for development assistance
- VTerm terminal integration with clipboard and mouse support
- Custom key bindings for efficient workflow
- Multi-language development support (JavaScript/TypeScript, Ruby, Gleam, Clojure)
- Project management with Projectile
- Theme management and appearance customization

**Configuration Files:**

- `config.org`: Main literate configuration (tangled to config.el)
- `init.el`: Doom modules and feature enablement
- `packages.el`: Additional package declarations
- `install-emacs-doom-mac.sh`: macOS installation script

### nvf (Neovim Configuration)

**Secondary Editor**: nvf provides a minimal, declarative Neovim setup.

**Key Features:**

- Fully declarative configuration via Nix
- Modular plugin system
- Cross-platform support (Linux, macOS, WSL)
- LSP, completion, and modern Neovim features

**Useful Commands:**

```bash
# Print generated Neovim configuration
nvf-print-config

# Print with syntax highlighting
nvf-print-config | bat --language=lua

# Get path to generated config
nvf-print-config-path
```

**Resources:**

- [nvf Documentation](https://notashelf.github.io/nvf/)
- [nvf Options Reference](https://notashelf.github.io/nvf/options.html)
- Local README: `users/jordangarrison/tools/nvim/README.md`

This configuration provides a fully reproducible, declarative system environment across multiple platforms and users, with consistent development tooling and user experience.
