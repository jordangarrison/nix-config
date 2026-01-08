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
| `opportunity` | Framework 13 (13th Gen Intel) | Laptop with GNOME and Hyprland |
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
│   ├── endeavour/            # Desktop workstation (NixOS)
│   ├── opportunity/          # Framework laptop (NixOS)
│   ├── voyager/              # MacBook Pro (NixOS)
│   ├── discovery/            # AMD system (NixOS)
│   └── flomac/               # Work MacBook (nix-darwin)
├── modules/
│   ├── nixos/                # Shared NixOS modules
│   │   ├── common.nix        # Base system configuration
│   │   ├── gnome-desktop.nix # GNOME desktop environment
│   │   ├── hyprland-desktop.nix # Hyprland compositor
│   │   ├── niri-desktop.nix  # Niri scrollable compositor
│   │   ├── development.nix   # Docker, Emacs, dev tools
│   │   └── audio/            # Audio configurations
│   └── home/                 # Home Manager modules
│       ├── niri/             # Niri user configuration
│       ├── hyprland/         # Hyprland user configuration
│       ├── brave/            # Browser app integration
│       └── alacritty/        # Terminal configuration
├── users/                    # User configurations
│   ├── jordangarrison/       # Primary user
│   │   ├── nixos.nix         # NixOS user module
│   │   ├── home.nix          # Core Home Manager config
│   │   ├── home-linux.nix    # Linux-specific settings
│   │   ├── home-darwin.nix   # macOS-specific settings
│   │   ├── configs/          # Application configs (hypr, etc.)
│   │   ├── tools/            # Custom scripts and tools
│   │   └── wallpapers/       # Wallpaper collection
│   ├── mikayla/              # Family member configurations
│   ├── jane/
│   └── isla/
├── docs/
│   └── adr/                  # Architecture Decision Records
├── packages/                 # Custom package definitions
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
- **Modular** - Shared modules for common functionality
- **Development ready** - Emacs (Doom), Neovim (nvf), Docker, and more

## Documentation

- **[AGENTS.md](./AGENTS.md)** - Detailed guidance for AI agents and comprehensive architecture documentation
- **[docs/adr/](./docs/adr/)** - Architecture Decision Records

## Initial Setup

For non-NixOS systems, install Nix using the Determinate Systems installer:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```
