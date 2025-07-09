# My Nix Configuration

Jordan Garrison's NixOS and Home Manager configurations for NixOS and macOS.

## Setup

### NixOS

1. Clone the repository to your local machine
2. Build and switch to the configuration:

   ```bash
   sudo nixos-rebuild switch --flake .#<hostname>
   ```

Available hosts:

- `endeavour` - Main desktop workstation
- `voyager` - MacBook Pro running NixOS

### macOS (nix-darwin)

1. Clone the repository to your local machine
2. Build and switch to the configuration:

   ```bash
   sudo darwin-rebuild switch --flake .#<hostname>
   ```

Available hosts:

- `H952L3DPHH` - Work MacBook

### Home Manager (WSL/Ubuntu)

1. Clone the repository to your local machine
2. Build and switch to the configuration:

   ```bash
   home-manager switch --flake .#<config>
   ```

Available configurations:

- `jordangarrison@normandy` - WSL/Ubuntu setup

## Structure

```
├── flake.nix              # Main flake configuration
├── hosts/                 # Host-specific configurations
│   ├── endeavour/         # Desktop workstation
│   ├── voyager/           # MacBook Pro
│   └── flomac/            # Work MacBook
├── modules/               # Shared NixOS modules
│   ├── nixos/             # NixOS-specific modules
│   └── *.nix              # Standalone modules
└── users/                 # User configurations
    ├── jordangarrison/    # Jordan's user config
    │   ├── nixos.nix      # NixOS user module
    │   ├── home.nix       # Home Manager config
    │   ├── configs/       # User-specific configs
    │   └── tools/         # User-specific tools
    └── <other-users>/     # Other family members
```

## Updates

### Updating Dependencies

Update flake inputs (equivalent to updating channels):

```bash
nix flake update
```

### Rebuilding Systems

After updating, rebuild your system:

```bash
# NixOS
sudo nixos-rebuild switch --flake .#<hostname>

# macOS
sudo darwin-rebuild switch --flake .#<hostname>

# Home Manager only
home-manager switch --flake .#<config>
```

## Features

- **Flake-based configuration** - Reproducible and version-locked
- **Multi-platform support** - NixOS, macOS, and WSL/Ubuntu
- **Modular user management** - Each user has their own folder with nixos.nix and home.nix
- **Host-specific configurations** - Easy to manage different machines
- **Shared modules** - Common functionality across all hosts
