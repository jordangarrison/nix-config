# Neovim Configuration with nvf

This directory contains the Neovim configuration using [nvf](https://github.com/NotAShelf/nvf), a highly modular, configurable, extensible and easy to use Neovim configuration in Nix.

## Overview

nvf is a Neovim configuration framework that allows you to configure a fully featured Neovim instance using Nix. It provides:

- **Modular**: Each feature is a separate module that can be enabled/disabled
- **Reproducible**: Your configuration will behave the same everywhere
- **Declarative**: Configure everything through Nix options
- **Extensible**: Easy to add custom plugins and configurations

## Files

- `nvf.nix` - Main nvf configuration module
- `nvim.nix.backup` - Backup of previous nixvim configuration (for reference)
- `jag.lua.backup` - Backup of previous Lua configuration (for reference)

## Current Configuration

The current setup is minimal and includes:

```nix
{
  programs.nvf = {
    enable = true;
    settings = {
      vim.viAlias = false;
      vim.vimAlias = true;
      vim.lsp = {
        enable = true;
      };
    };
  };
}
```

This provides:
- Basic Neovim with `vim` alias enabled
- LSP support enabled
- Clean, minimal starting point for customization

## Extending the Configuration

To add more features, you can extend the `settings.vim` configuration. Common options include:

### Theme and UI
```nix
vim.theme = {
  enable = true;
  name = "tokyonight";
};
```

### File Tree
```nix
vim.filetree.nvimTree.enable = true;
```

### Telescope (Fuzzy Finder)
```nix
vim.telescope.enable = true;
```

### Git Integration
```nix
vim.git = {
  enable = true;
  gitsigns.enable = true;
};
```

### Language Support
```nix
vim.languages = {
  nix.enable = true;
  typescript.enable = true;
  go.enable = true;
  python.enable = true;
  rust.enable = true;
  # ... and many more
};
```

### Completion and Snippets
```nix
vim.autocomplete = {
  enable = true;
  type = "nvim-cmp";
};
vim.snippets.luasnip.enable = true;
```

## Migration from Previous Setup

The previous setup used a combination of:
1. **nixvim** - A Nix-based Neovim configuration (was commented out)
2. **Plain Neovim** - Basic Neovim package with custom Lua config
3. **Kickstart.nvim-based config** - The `jag.lua` file was based on kickstart.nvim

### What Changed
- ✅ Neovim package removed from `home.packages`
- ✅ nvf module imported in `home.nix`
- ✅ Old configurations backed up
- ✅ Minimal nvf configuration in place

### Next Steps
You can gradually migrate features from the backup configurations:

1. **Language Servers**: The kickstart config had LSP setup for various languages
2. **Key Mappings**: Custom keybindings can be added via `vim.keymaps`
3. **Plugins**: Popular plugins like telescope, treesitter were configured
4. **Autocommands**: Custom autocommands can be added via `vim.luaConfigRC`

## Testing nvf

To test your nvf configuration:

```bash
# Check flake syntax
nix flake check

# Build without switching
nh os build .

# Switch to new configuration (after testing)
nh os switch .
```

## Useful nvf Commands

```bash
# Print the generated Neovim configuration
nvf-print-config

# Print with syntax highlighting
nvf-print-config | bat --language=lua

# Get path to generated config
nvf-print-config-path
```

## Resources

- [nvf Documentation](https://notashelf.github.io/nvf/)
- [nvf GitHub Repository](https://github.com/NotAShelf/nvf)
- [nvf Options Reference](https://notashelf.github.io/nvf/options.html)
- [Home Manager nvf Module](https://notashelf.github.io/nvf/index.xhtml#ch-standalone-hm)

## Configuration Examples

For inspiration, check out:
- The built-in `nix` and `maximal` configurations: `nix run github:notashelf/nvf#nix`
- Other users' nvf configurations in the community
- The nvf documentation examples

## Contributing Back

If you create useful nvf modules or configurations, consider contributing them back to the nvf project to help the community!
