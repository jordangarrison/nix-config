# ADR-001: Migrate Traditional Dotfiles to Home Manager Modules

## Status

Proposed

## Context

Currently using a hybrid approach where Nix manages packages and programs but traditional dotfiles handle shell customization, aliases, and functions. The existing setup includes:

- **Traditional dotfiles repository** at `~/dev/jordan.andrew.garrison/dotfiles`
- **Modular shell configuration** with 20+ source files in `source_files/`
- **100+ shell aliases** with platform-specific logic (macOS vs Linux)
- **50+ custom shell functions** for system monitoring, Kubernetes, development workflows
- **Comprehensive tool configurations** (alacritty, doom emacs, iterm2, git, etc.)
- **Platform separation** with dedicated mac/, linux/, nix/ directories

The current Nix home-manager configuration references the traditional dotfiles with:

```nix
source ~/.dotfiles/zshrc
```

This creates a dependency on external dotfiles that are not version-controlled with the Nix configuration, reducing reproducibility.

## Decision

Migrate the traditional dotfiles into a modular Home Manager configuration structure to achieve full reproducibility while preserving the existing modular organization and workflow patterns.

## Proposed Module Structure

```txt
users/jordangarrison/modules/
├── shell/
│   ├── zsh.nix           # Core zsh config + oh-my-zsh setup
│   ├── aliases.nix       # All shell aliases (100+ aliases)
│   ├── functions.nix     # Custom shell functions (50+ functions)
│   └── starship.nix      # Prompt configuration
├── development/
│   ├── git.nix           # Git config + aliases from gitconfig
│   ├── editors.nix       # vim, emacs, vscode configurations
│   ├── languages.nix     # Language-specific tools and settings
│   └── kubernetes.nix    # k8s tools + custom k8s functions
├── desktop/
│   ├── terminals.nix     # alacritty, wezterm, ghostty configs
│   ├── browsers.nix      # brave, firefox configurations
│   └── applications.nix  # GUI applications and settings
├── platform/
│   ├── linux.nix         # Linux-specific configurations
│   ├── darwin.nix        # macOS-specific configurations
│   └── common.nix        # Shared cross-platform configurations
└── services/
    ├── aws.nix           # AWS tools + profile management functions
    └── work.nix          # FloSports-specific functions and aliases
```

## Migration Strategy

### Phase 1: Core Shell Configuration

1. **Analyze current dotfiles structure** ✅
2. **Design modular home-manager structure** ✅
3. **Create shell configuration module** - Convert zsh config, oh-my-zsh setup
4. **Migrate aliases** - Convert 100+ aliases from `20_aliases.sh` to Nix format
5. **Migrate functions** - Convert 50+ functions from `30_functions.sh` to Nix format

### Phase 2: Development Tools

6. **Create development tools module** - Git config, editors, language tools
7. **Migrate git configuration** - Convert comprehensive gitconfig with aliases
8. **Setup editor configurations** - vim, emacs, vscode settings

### Phase 3: Desktop & Platform

9. **Create desktop applications module** - Terminal emulators, GUI apps
10. **Create platform-specific modules** - Handle Linux vs macOS differences
11. **Migrate individual config files** - alacritty, wezterm, etc.

### Phase 4: Integration & Testing

12. **Test the new modular setup** - Validate on test system
13. **Update flake.nix** - Integrate new modular structure
14. **Gradual rollout** - Deploy to each system (endeavour, voyager, flomac)

## Key Components to Migrate

### Shell Configuration

- **zshrc** - Main shell config with oh-my-zsh "nebirhos" theme
- **source_files/** - 20+ modular configuration files:
  - `00_environment.sh` - Environment variables
  - `20_aliases.sh` - 100+ aliases with platform logic
  - `30_functions.sh` - Custom functions (cpuproc, memproc, k8s helpers)
  - `40_*.sh` - Tool completions (nix, deno, vscode)
  - `50_*.sh` - Kubernetes tools (krew, kustomize)
  - `60_*.sh` - Project-specific configs

### Development Tools

- **gitconfig** - Comprehensive git aliases and settings
- **Editor configs** - doom emacs, vim, vscode settings
- **Language tools** - Go, Node.js, Python, Rust configurations

### Desktop Applications

- **Terminal emulators** - alacritty, wezterm, iterm2 configs
- **GUI applications** - Browser extensions, desktop apps

## Implementation Approach

### Nix Module Pattern

Each module will follow this pattern:

```nix
{ config, pkgs, lib, ... }:
{
  options.jordangarrison.shell = {
    enable = lib.mkEnableOption "Jordan's shell configuration";
    # Additional options as needed
  };

  config = lib.mkIf config.jordangarrison.shell.enable {
    # Module implementation
  };
}
```

### Platform Handling

Use conditional logic for platform-specific configurations:

```nix
programs.zsh.shellAliases = {
  # Common aliases
  l = "ls -ltarh";
  ll = "ls -lh";
} // lib.optionalAttrs pkgs.stdenv.isDarwin {
  # macOS-specific aliases
  e = "open";
  copy = "pbcopy";
} // lib.optionalAttrs pkgs.stdenv.isLinux {
  # Linux-specific aliases
  e = "xdg-open";
  copy = "xclip -selection clipboard";
};
```

## Consequences

### Positive

- **Full reproducibility** - All configurations version-controlled in Nix
- **Modular organization** - Enable/disable features per system
- **Platform awareness** - Conditional loading based on OS
- **Maintainability** - Organized by function rather than single large files
- **Consistency** - Same configuration approach across all systems
- **Rollback capability** - Easy to revert changes with Nix generations

### Negative

- **Initial migration effort** - Significant time investment to convert all configs
- **Learning curve** - Need to understand Nix configuration syntax
- **Temporary workflow disruption** - During migration period
- **Potential complexity** - More complex than simple shell scripts
- **Debugging challenges** - Nix error messages can be cryptic

### Risks & Mitigations

- **Risk**: Breaking existing workflow during migration
  - **Mitigation**: Gradual migration with fallback to original dotfiles
- **Risk**: Loss of functionality during conversion
  - **Mitigation**: Thorough testing on each system before full deployment
- **Risk**: Nix-specific limitations
  - **Mitigation**: Keep complex functions as external scripts if needed

## Success Criteria

1. **Functional parity** - All existing aliases and functions work identically
2. **Platform compatibility** - Proper behavior on Linux (endeavour, voyager) and macOS (flomac)
3. **Reproducibility** - Fresh system deployment produces identical environment
4. **Maintainability** - Easy to add/modify configurations
5. **Performance** - No significant shell startup time regression

## Timeline

- **Week 1-2**: Phase 1 (Shell configuration)
- **Week 3**: Phase 2 (Development tools)
- **Week 4**: Phase 3 (Desktop & platform)
- **Week 5**: Phase 4 (Integration & testing)

## References

- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Nix Pills](https://nixos.org/guides/nix-pills/)
- [Current dotfiles repository](~/dev/jordan.andrew.garrison/dotfiles)
- [Current nix-config](~/dev/jordangarrison/nix-config)
