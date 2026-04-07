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

Core Infrastructure:
- `nixpkgs`: Main package repository (nixos-unstable)
- `nixpkgs-stable`: Stable channel (nixos-25.11) for specific packages
- `nixpkgs-master`: Latest master branch for bleeding-edge packages
- `nixos-hardware`: Hardware-specific configurations
- `nix-darwin`: macOS system management
- `home-manager`: User environment management

Desktop Environment:
- `niri`: Scrollable-tiling Wayland compositor
- `noctalia`: Unified desktop shell (bar, notifications, launcher, lock screen)
- `nix-zed-extensions`: Zed editor extensions via Nix

Development Tools:
- `nvf`: Highly modular Neovim configuration framework
- `llm-agents`: LLM tools including vibe-kanban MCP server
- `grove`: GitHub visualization tool

Jordan's Custom Flakes:
- `aws-tools`: AWS utilities
- `aws-use-sso`: AWS SSO helper
- `hubctl`: Container management utility
- `sweet-nothings`: Custom utility
- `greenlight`: GitHub repository dashboard
- `lakeline-cg`: Custom service (private Forgejo)

**Outputs:**

- `nixosConfigurations`: Full NixOS system configurations
- `darwinConfigurations`: macOS system configurations
- `homeConfigurations`: Standalone Home Manager configurations

### Overlay System

The repository uses overlays to customize and extend nixpkgs. Overlays are in `modules/`:

| Overlay | Purpose |
|---------|---------|
| `stable-overlay.nix` | Packages from nixpkgs-stable (25.11) |
| `master-overlay.nix` | Packages from nixpkgs-master (bleeding edge) |
| `zed-extensions-overlay.nix` | Zed IDE extensions via nix-zed-extensions |
| `llm-agents-overlay.nix` | LLM tools including vibe-kanban-mcp |
| `ralph-overlay.nix` | Custom ralph package |
| `scripts-overlay.nix` | Custom scripts from packages/ |
| `okta-cli-client-overlay.nix` | Okta CLI customizations |
| `sidecar-overlay.nix` | Sidecar utility |
| `tea-overlay.nix` | Tea CLI tool |

Overlays are imported per-host in `flake.nix` and make packages available via `pkgs.stable.*`, `pkgs.master.*`, etc.

### Custom Packages

The `packages/` directory contains custom package definitions:

| Package | Description |
|---------|-------------|
| `claude-switch` | Claude Code session switcher |
| `gi` | Git interactive helper |
| `ksn` | Kubernetes namespace switcher |
| `myip` | IP address checker |
| `ralph` | Custom utility |
| `sidecar` | Sidecar utility |
| `td` | Todo utility |
| `tmux-cht` | Tmux cheatsheet helper |
| `okta-cli-client` | Okta CLI with customizations |

Packages are built using `lib/mkScript.nix` for shell scripts.

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
│   ├── endeavour/            # Desktop workstation (NixOS) - services hub
│   ├── opportunity/          # Framework 12 laptop (NixOS) - tablet mode
│   ├── voyager/              # MacBook Pro (NixOS)
│   ├── discovery/            # AMD system (NixOS)
│   └── flomac/               # Work MacBook (nix-darwin)
├── users/                    # User configurations
│   ├── jordangarrison/       # Primary user
│   │   ├── nixos.nix         # NixOS user module
│   │   ├── home.nix          # Core Home Manager config
│   │   ├── home-linux.nix    # Linux-specific Home Manager
│   │   ├── home-darwin.nix   # macOS-specific Home Manager
│   │   ├── configs/          # Application configurations (hypr, noctalia, etc.)
│   │   ├── tools/            # Custom scripts and tools
│   │   │   ├── doom.d/       # Emacs Doom configuration
│   │   │   ├── nvim/         # Neovim (nvf) configuration
│   │   │   └── scripts/      # Shell scripts and utilities
│   │   └── wallpapers/       # Wallpaper collection
│   ├── mikayla/              # Family member configurations
│   ├── jane/                 # (Similar structure for each user)
│   └── isla/
├── modules/
│   ├── nixos/                # Shared NixOS modules (25 modules)
│   │   ├── common.nix        # Base system configuration
│   │   ├── gnome-desktop.nix # GNOME desktop environment
│   │   ├── hyprland-desktop.nix # Hyprland compositor
│   │   ├── niri-desktop.nix  # Niri scrollable compositor
│   │   ├── tablet-mode.nix   # Tablet mode (hardware sensors)
│   │   ├── development.nix   # Docker, Emacs, dev tools
│   │   ├── fonts.nix         # System fonts
│   │   ├── audio/pipewire.nix # Audio configuration
│   │   ├── blocky.nix        # DNS-level ad blocking
│   │   ├── forgejo.nix       # Self-hosted Git server
│   │   ├── forgejo-runner.nix # CI/CD action runners
│   │   ├── greenlight.nix    # GitHub dashboard service
│   │   ├── jellyfin.nix      # Media server with GPU transcoding
│   │   ├── nginx.nix         # Reverse proxy
│   │   ├── postgres.nix      # PostgreSQL database
│   │   ├── searx.nix         # Privacy-respecting search
│   │   └── ...               # See full list below
│   ├── home/                 # Home Manager modules (16 modules)
│   │   ├── defaults.nix      # Default home-manager settings
│   │   ├── niri/             # Niri user configuration
│   │   ├── hyprland/         # Hyprland user configuration
│   │   ├── tablet-mode/      # Gesture daemon and OSK
│   │   ├── ghostty/          # Ghostty terminal emulator
│   │   ├── wezterm/          # WezTerm terminal
│   │   ├── zed-editor/       # Zed code editor
│   │   ├── tea/              # Forgejo CLI configuration
│   │   ├── languages/        # Programming language tools
│   │   ├── brave/            # Browser app integration
│   │   ├── alacritty/        # Terminal shortcuts
│   │   └── ...               # See full list below
│   └── *-overlay.nix         # Package overlays (9 modules)
├── packages/                 # Custom package definitions (10 packages)
│   ├── claude-switch/        # Claude Code session switcher
│   ├── gi/                   # Git interactive helper
│   ├── ksn/                  # Kubernetes namespace switcher
│   ├── myip/                 # IP address checker
│   ├── ralph/                # Custom utility
│   ├── sidecar/              # Sidecar utility
│   ├── td/                   # Todo utility
│   └── tmux-cht/             # Tmux cheatsheet
├── lib/                      # Nix helper functions
│   └── mkScript.nix          # Script packaging helper
├── docs/                     # Documentation
│   ├── adr/                  # Architecture Decision Records
│   ├── plans/                # Implementation plans
│   ├── lessons-learned/      # Post-implementation learnings
│   └── agents/               # Agent-specific documentation
└── shell.nix                 # Development shell
```

## NixOS Modules Reference

The `modules/nixos/` directory contains 25 shared modules organized by function:

### Desktop Environments

| Module | Description |
|--------|-------------|
| `common.nix` | Base system configuration (networking, locale, Tailscale, 1Password) |
| `gnome-desktop.nix` | GNOME desktop with extensions and configuration |
| `hyprland-desktop.nix` | Hyprland dynamic tiling compositor |
| `niri-desktop.nix` | Niri scrollable-tiling compositor with noctalia shell |
| `tablet-mode.nix` | Hardware sensor support for touchscreen devices |
| `fonts.nix` | System-wide font configuration |
| `audio/pipewire.nix` | PipeWire audio with low-latency configuration |

### Development Tools

| Module | Description |
|--------|-------------|
| `development.nix` | Docker, development tools, language runtimes |
| `emacs.nix` | Emacs system integration (also used on Darwin) |
| `virtualization.nix` | libvirt/QEMU/KVM virtual machine support |
| `podman.nix` | Podman container runtime |

### Infrastructure Services (endeavour)

These modules configure services running on the endeavour desktop as a home server:

| Module | Description | Port/URL |
|--------|-------------|----------|
| `nginx.nix` | Reverse proxy with ACME certificates | 80, 443 |
| `postgres.nix` | PostgreSQL database with Tailscale access | 5432 |
| `blocky.nix` | DNS-level ad blocking | 53 |
| `forgejo.nix` | Self-hosted Git server | forgejo.jordangarrison.dev |
| `forgejo-runner.nix` | CI/CD action runners (Docker + native) | - |
| `greenlight.nix` | GitHub repository dashboard | greenlight.jordangarrison.dev |
| `jellyfin.nix` | Media server with AMD GPU transcoding | jellyfin.jordangarrison.dev |
| `searx.nix` | Privacy-respecting metasearch engine | searx.jordangarrison.dev |
| `metabase.nix` | Analytics and BI platform | - |
| `n8n.nix` | Low-code workflow automation | - |
| `lakeline-cg.nix` | Custom service integration | - |

### Hardware & Networking

| Module | Description |
|--------|-------------|
| `lan.nix` | LAN-specific networking configuration |
| `brother-printer.nix` | Brother printer integration |
| `freerdp.nix` | Remote desktop protocol support |
| `steam.nix` | Steam gaming platform |

## Home Manager Modules Reference

The `modules/home/` directory contains 16 user-level configuration modules:

### Terminal Emulators

| Module | Description |
|--------|-------------|
| `alacritty/` | Alacritty terminal with app shortcuts |
| `ghostty/` | Ghostty terminal (Rose Pine theme, shell integration) |
| `wezterm/` | WezTerm with SSH apps and workspace integration |

### Desktop Environment

| Module | Description |
|--------|-------------|
| `niri/` | Niri user configuration (keybindings, layout, animations) |
| `hyprland/` | Hyprland user configuration |
| `tablet-mode/` | Touchscreen gestures (lisgd) and on-screen keyboard (wvkbd) |
| `rofi/` | Application launcher |
| `wlr-which-key/` | Wayland keybinding hints |
| `desktop-tools/` | Desktop utilities collection |

### Development

| Module | Description |
|--------|-------------|
| `zed-editor/` | Zed IDE with Doom-style keybindings and extensions |
| `languages/` | Programming language tools (Gleam, Ruby) |
| `tea/` | Forgejo/Gitea CLI with declarative login configuration |
| `virt-manager/` | Virtual machine GUI configuration |

### Browser & Apps

| Module | Description |
|--------|-------------|
| `brave/` | Brave browser with extensions and web apps |
| `defaults.nix` | Default home-manager settings |

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

### DNS Management (Cloudflare)

DNS records for `jordangarrison.dev` are managed via Cloudflare. The `flarectl` CLI is available as a wrapped package that automatically sources the API token from `/var/lib/acme-secrets/cloudflare-env` (the same credentials used by ACME/Let's Encrypt).

```bash
# List all DNS records
flarectl dns list --zone jordangarrison.dev

# Create a new A record (self-hosted services use the Tailscale IP 100.118.65.11)
flarectl dns create --zone jordangarrison.dev --name <subdomain> --type A --content 100.118.65.11 --ttl 1

# Create a CNAME record
flarectl dns create --zone jordangarrison.dev --name <subdomain> --type CNAME --content <target> --ttl 1

# Update an existing record
flarectl dns update --zone jordangarrison.dev --id <record-id> --content <new-content>

# Delete a record
flarectl dns delete --zone jordangarrison.dev --id <record-id>
```

**Convention for self-hosted services:** Use an A record pointing to `100.118.65.11` (Tailscale IP for endeavour), with TTL `1` (auto) and proxy disabled. This matches the pattern used by forgejo, greenlight, jellyfin, and searx.

**Wrapper details:** The `flarectl` command is a wrapper (`packages/flarectl/flarectl-wrapper.sh`) defined in `modules/scripts-overlay.nix`. It sources the Cloudflare token automatically — no manual `CF_API_TOKEN` export needed.

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

### Infrastructure Services (endeavour)

The endeavour desktop doubles as a home server running several self-hosted services:

**Git & CI/CD:**
- **Forgejo** - Self-hosted Git server at forgejo.jordangarrison.dev
- **Forgejo Action Runners** - Docker and native runners for CI/CD pipelines
- **Tea CLI** - Configured via `programs.tea` for command-line access

**Media & Search:**
- **Jellyfin** - Media server with AMD GPU VAAPI hardware transcoding
- **Searx** - Privacy-respecting metasearch engine with Redis backend

**Development Tools:**
- **Greenlight** - GitHub repository dashboard tracking personal and work projects
- **PostgreSQL** - Database with Tailscale network access (100.x.x.x subnet)
- **Metabase** - Analytics and BI platform

**Networking:**
- **Nginx** - Reverse proxy with ACME certificates for *.jordangarrison.dev domains
- **Blocky** - DNS-level ad blocking with allowlists for Datadog/Claude telemetry

**Service Management Commands:**

```bash
# Check service status
systemctl status forgejo
systemctl status jellyfin
systemctl status blocky

# View service logs
journalctl -u forgejo -f
journalctl -u nginx -f

# Restart a service
sudo systemctl restart forgejo
```

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

### Zed Editor

**Alternative IDE**: Zed configured with Doom-style keybindings and Nix extensions.

**Key Features:**

- Managed via `modules/home/zed-editor/`
- Extensions installed via nix-zed-extensions overlay
- Doom-style keybindings for familiar editing
- SSH configuration for remote development

## Documentation Structure

The `docs/` directory contains project documentation:

### Architecture Decision Records (ADRs)

Located in `docs/adr/`, these document significant architectural decisions:

- `001-migrate-dotfiles-to-home-manager.md`
- `002-migrate-desktop-to-hyprland.md`
- `003-add-niri-scrolling-compositor.md`
- `004-add-tablet-mode-support.md`

### Implementation Plans

Located in `docs/plans/`, these contain detailed implementation plans for features before they are built. Plans cover scope, approach, and acceptance criteria.

### Lessons Learned

Located in `docs/lessons-learned/`, these capture insights from implementing features, including what worked well and what to avoid.

### Agent Documentation

Located in `docs/agents/`, this contains agent-specific documentation and context.

This configuration provides a fully reproducible, declarative system environment across multiple platforms and users, with consistent development tooling and user experience.
