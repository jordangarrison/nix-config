# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is Jordan Garrison's personal Nix configuration repository using Nix Flakes for declarative system management across multiple platforms. It supports NixOS, macOS (via nix-darwin), and WSL/Ubuntu (via Home Manager only).

## Essential Commands

### System Rebuilding (Primary method using nh)
```bash
# NixOS systems
nh os switch .#<hostname>

# macOS systems (nix-darwin)  
nh darwin switch .#<hostname>

# Home Manager only (WSL/Ubuntu)
nh home switch .#<config>
```

### Fallback Commands (if nh unavailable)
```bash
# NixOS
sudo nixos-rebuild switch --flake .#<hostname>

# macOS
sudo darwin-rebuild switch --flake .#<hostname>

# Home Manager standalone
home-manager switch --flake .#<config>
```

### Package and Flake Management
```bash
# Update all flake inputs
nh flake update
# or: nix flake update

# Check flake configuration
nh flake check
# or: nix flake check

# Show flake outputs
nh flake show
# or: nix flake show

# Search for packages
nh search <package-name>

# Clean old generations
nh clean all

# Development shell
nix develop
```

### Available Configurations

**NixOS hosts:**
- `endeavour` - Main desktop workstation (MSI B550-A Pro, AMD GPU)
- `voyager` - MacBook Pro running NixOS 
- `discovery` - AMD system

**Darwin host:**
- `H952L3DPHH` - Work MacBook (nix-darwin)

**Home Manager config:**
- `jordangarrison@normandy` - WSL/Ubuntu setup

## Architecture Overview

### Flake Structure
The `flake.nix` orchestrates three types of configurations:
- **nixosConfigurations**: Full NixOS system configs with Home Manager integration
- **darwinConfigurations**: macOS system management via nix-darwin
- **homeConfigurations**: Standalone Home Manager for WSL/Ubuntu

### Key Inputs
- `nixpkgs` (nixos-unstable): Main package repository
- `nixos-hardware`: Hardware-specific configurations
- `home-manager`: User environment management
- `nix-darwin`: macOS system management
- Custom flakes: `aws-tools`, `aws-use-sso`, `hubctl` (Jordan's tools)

### Directory Architecture
```
├── flake.nix              # Central flake configuration
├── hosts/                 # Host-specific configurations
│   ├── endeavour/         # Desktop (NixOS)
│   ├── voyager/           # MacBook Pro (NixOS)
│   ├── discovery/         # AMD system (NixOS)
│   └── flomac/            # Work MacBook (nix-darwin)
├── users/                 # User configurations per person
│   ├── jordangarrison/    # Primary user
│   │   ├── nixos.nix      # System-level user config
│   │   ├── home.nix       # Core Home Manager config
│   │   ├── home-linux.nix # Linux-specific Home Manager
│   │   ├── home-darwin.nix# macOS-specific Home Manager
│   │   ├── configs/       # App configurations (hypr, ssh)
│   │   └── tools/         # Custom scripts and app configs
│   ├── mikayla/           # Family member configurations
│   ├── jane/              # (Each user has nixos.nix)
│   └── isla/
├── modules/
│   ├── nixos/             # Shared NixOS modules
│   │   ├── common.nix     # Base system configuration
│   │   ├── development.nix# Docker, dev tools
│   │   ├── gnome-desktop.nix
│   │   └── hyprland-desktop.nix
│   └── home/              # Home Manager modules
└── shell.nix              # Development shell
```

### User Configuration Pattern
Each user follows this pattern:
- `nixos.nix`: System-level user account, groups, sudo access
- `home.nix`: Cross-platform Home Manager configuration
- `home-linux.nix`: Linux-specific settings (GNOME, workspaces)
- `home-darwin.nix`: macOS-specific settings (Homebrew, paths)

### Multi-User Family Setup
The configuration supports multiple family members (jordangarrison, mikayla, jane, isla) with:
- Individual user modules in `users/<name>/nixos.nix`
- Shared system modules from `modules/nixos/`
- Per-host user enablement in `flake.nix`

## Development Workflow

### Adding System Packages
```nix
# System-wide packages (affects all users)
# Edit: modules/nixos/common.nix
environment.systemPackages = with pkgs; [ new-package ];

# User-specific packages
# Edit: users/jordangarrison/home.nix  
home.packages = with pkgs; [ new-package ];
```

### Update Process
1. `nh flake update` (or `nix flake update`)
2. Review changes: `git diff flake.lock`
3. Rebuild with appropriate command for platform
4. Commit: `git add flake.lock && git commit -m "Update flake inputs"`

### Development Environment
Use `nix develop` to enter shell with: git, home-manager, neovim, nix (with flakes enabled).

## Platform-Specific Features

### NixOS Systems
- AppImage and Flatpak support enabled
- Tailscale networking configured
- Docker enabled for development
- 1Password GUI with policy ownership for Jordan

### GNOME Configuration (Linux)
- 10 fixed workspaces (Super+1-0 shortcuts)
- Auto-move-windows extension for application workspace assignment
- Application shortcuts: Super+B (Brave), Super+W (Warp), Super+C (Cursor)
- Extensions: AppIndicator, Clipboard History, Fuzzy App Search, GSConnect

### Custom Tools Integration
Jordan's custom tools are included via flake inputs:
- `aws-tools`: AWS utilities
- `aws-use-sso`: AWS SSO helper  
- `hubctl`: Container management utility

These are automatically built from their repositories and included in home.nix packages.

## Maintenance Notes

### Git Configuration
- All git commands configured with `--no-pager` flag by default
- Enhanced diff display with diff-so-fancy
- Aliases: gss, pu, gd, gdca

### SSH Configuration
- Managed via Home Manager in `users/jordangarrison/configs/ssh/config`
- Permissions fixed via onChange hook to handle symlink issues

### Custom Scripts
Located in `users/jordangarrison/tools/scripts/` and added to PATH via Home Manager. Include utilities for AWS, tmux, wallpapers, and IP checking.