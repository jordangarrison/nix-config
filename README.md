# Nix Configuration

Jordan Garrison's declarative system configurations for NixOS, macOS (nix-darwin), and WSL/Ubuntu (Home Manager) using Nix Flakes.

## Quick Start

This repository uses [nh](https://github.com/viperML/nh) for an improved Nix experience. All commands below assume `nh` is installed.

### NixOS

```bash
# Clone and switch to a configuration
git clone https://github.com/jordangarrison/nix-config.git
cd nix-config
nh os switch .#<hostname>
```

**Available NixOS hosts:**

| Host | Hardware | Description |
|------|----------|-------------|
| `endeavour` | MSI B550-A Pro, AMD GPU | Main desktop workstation with GNOME, Hyprland, and Niri |
| `opportunity` | Framework 12 (13th Gen Intel) | Laptop with GNOME, Hyprland, and Niri. **Tablet mode enabled** (touchscreen gestures, auto-rotation, OSK) |
| `voyager` | MacBook Pro 12,1 | MacBook Pro running NixOS |
| `discovery` | AMD-based system | Minimal GNOME setup |

### macOS (nix-darwin)

```bash
nh darwin switch .#<hostname>
```

**Available Darwin hosts:**

| Host | Description |
|------|-------------|
| `H952L3DPHH` | Work MacBook with Home Manager integration |

### WSL/Ubuntu (Home Manager only)

```bash
nh home switch .#<config>
```

**Available Home Manager configurations:**

| Config | Description |
|--------|-------------|
| `jordangarrison@normandy` | WSL/Ubuntu standalone setup |

## Directory Structure

```
├── flake.nix                 # Central flake configuration
├── hosts/                    # Host-specific configurations
│   ├── endeavour/            # Desktop workstation + home server (NixOS)
│   ├── opportunity/          # Framework 12 laptop with tablet mode (NixOS)
│   ├── voyager/              # MacBook Pro (NixOS)
│   ├── discovery/            # AMD system (NixOS)
│   └── flomac/               # Work MacBook (nix-darwin)
├── modules/
│   ├── nixos/                # Shared NixOS modules (25 modules)
│   │   ├── common.nix        # Base system configuration
│   │   ├── gnome-desktop.nix # GNOME desktop environment
│   │   ├── niri-desktop.nix  # Niri scrollable compositor
│   │   ├── tablet-mode.nix   # Tablet mode (hardware sensors)
│   │   ├── development.nix   # Docker, Emacs, dev tools
│   │   ├── forgejo.nix       # Self-hosted Git server
│   │   ├── jellyfin.nix      # Media server
│   │   ├── nginx.nix         # Reverse proxy
│   │   └── ...               # And more (see AGENTS.md)
│   ├── home/                 # Home Manager modules (16 modules)
│   │   ├── niri/             # Niri user configuration
│   │   ├── tablet-mode/      # Tablet gestures and OSK
│   │   ├── tea/              # Forgejo CLI
│   │   ├── zed-editor/       # Zed IDE
│   │   ├── ghostty/          # Ghostty terminal
│   │   └── ...               # And more (see AGENTS.md)
│   └── *-overlay.nix         # Package overlays (9 modules)
├── packages/                 # Custom package definitions (10 packages)
├── users/                    # User configurations
│   ├── jordangarrison/       # Primary user
│   │   ├── configs/          # Application configs
│   │   ├── tools/            # Doom Emacs, nvf, scripts
│   │   └── wallpapers/       # Wallpaper collection
│   └── mikayla/, jane/, isla/ # Family member configurations
├── lib/                      # Nix helper functions
├── docs/                     # Documentation
│   ├── adr/                  # Architecture Decision Records
│   ├── plans/                # Implementation plans
│   └── lessons-learned/      # Post-implementation learnings
└── shell.nix                 # Development shell
```

## Desktop Environments

The configuration supports multiple desktop environments, selectable at login:

| DE | Description | Hosts |
|----|-------------|-------|
| **GNOME** | Traditional desktop with extensions | All NixOS hosts |
| **Hyprland** | Dynamic tiling Wayland compositor | endeavour, opportunity, voyager |
| **Niri** | Scrollable-tiling Wayland compositor | endeavour |

## Managing the System

### Update Dependencies

```bash
# Update all flake inputs
nix flake update

# Review changes
git diff flake.lock
```

### Rebuild System

```bash
# NixOS
nh os switch .#<hostname>

# macOS
nh darwin switch .#<hostname>

# Home Manager only
nh home switch .#<config>
```

### Other Commands

```bash
# Search for packages
nh search <package-name>

# Check flake configuration
nix flake check

# Clean up old generations
nh clean all

# Enter development shell
nix develop
```

## Features

- **Flake-based** - Reproducible, version-locked configurations
- **Multi-platform** - NixOS, macOS, and WSL/Ubuntu support
- **Multi-user** - Family members have individual configurations
- **Multiple DEs** - GNOME, Hyprland, and Niri available
- **Tablet mode** - Touchscreen gestures, auto-rotation, and on-screen keyboard (opportunity)
- **Home server** - Self-hosted services on endeavour (Forgejo, Jellyfin, Searx, Greenlight)
- **Modular** - 25 NixOS modules + 16 Home Manager modules + 9 overlays
- **Development ready** - Emacs (Doom), Neovim (nvf), Zed, Docker, and more
- **Custom packages** - 10 custom utilities via packages/ directory

## Documentation

- **[AGENTS.md](./AGENTS.md)** - Comprehensive architecture documentation and AI agent guidance
- **[docs/adr/](./docs/adr/)** - Architecture Decision Records
- **[docs/plans/](./docs/plans/)** - Implementation plans for features
- **[docs/lessons-learned/](./docs/lessons-learned/)** - Post-implementation learnings

## Initial Setup

For non-NixOS systems, install Nix using the Determinate Systems installer:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```
