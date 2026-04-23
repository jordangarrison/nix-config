# Pi Home Manager Module

**Date:** 2026-04-24
**Status:** Approved

## Summary

Add a proper Home Manager module at `modules/home/pi/default.nix` to manage Jordan's global [pi](https://pi.dev) configuration declaratively on NixOS/macOS, while keeping authentication state mutable. The module should install a configurable pi package, generate core JSON config, publish module-owned prompts/themes/extensions into `~/.pi/agent/`, and optionally enable the tmux extended-key settings pi recommends.

This is a **global-first** design. It manages `~/.pi/agent/*` and intentionally does not try to solve project-local `.pi/*` overrides yet.

## Motivation

Pi is already installed in this repo via the `llm-agents.nix` overlay, but its user configuration is still mutable and lives outside the repo. Moving the stable parts of pi into Home Manager will:

- make the setup reproducible across rebuilds and machines
- keep pi configuration consistent with the rest of the repo's module-based design
- create a clean place for pi-specific prompts, themes, and extensions
- fix the current mismatch between a Nix-managed pi binary and ad-hoc per-user config

## Chosen approach

Three approaches were considered:

1. **Minimal wrapper**: install pi, write a couple JSON files, symlink raw resource directories
2. **Override-friendly resource module**: proper `programs.pi` module with defaults, overrides, and module-owned implementation files
3. **Fully generic resource framework**: abstract resource-merging framework for prompts/themes/extensions

This design chooses **Approach 2**.

### Why Approach 2

It best matches the newer conventions already used in this repo for modules like Ghostty and Niri:

- feature entry point lives in `modules/home/<feature>/default.nix`
- implementation details live alongside the module
- defaults are shipped by the module
- local customization happens through explicit options instead of scattered files

Approach 1 would be fast but too rigid. Approach 3 would be powerful but over-designed for the current need.

## Architecture

### Module location

```text
modules/home/pi/
├── default.nix
├── prompts/
│   ├── research.md
│   ├── review.md
│   └── nixos-change.md
├── themes/
│   └── jordangarrison.json
├── extensions/
│   ├── protected-paths.ts
│   └── status-line.ts
└── lib/
    └── resources.nix   # add only if resource merge logic becomes too large for default.nix
```

### Responsibilities

The `programs.pi` Home Manager module will:

- install the selected pi package via `programs.pi.package`
- generate `~/.pi/agent/settings.json`
- generate `~/.pi/agent/keybindings.json`
- publish prompts into `~/.pi/agent/prompts/`
- publish themes into `~/.pi/agent/themes/`
- publish extensions into `~/.pi/agent/extensions/`
- optionally manage tmux extended-key config needed for good pi terminal UX

### Explicit non-responsibilities

The module will **not** manage:

- `~/.pi/agent/auth.json`
- provider credentials or login state
- project-local `.pi/*` resources
- terminal-specific policy inside Ghostty/WezTerm/Alacritty modules

`auth.json` stays mutable so `/login`, API keys, and provider auth continue to work without fighting Home Manager.

## Materialization strategy

Pi uses `~/.pi/agent/*` rather than XDG paths, so this module should use `home.file`, not `xdg.configFile`.

Managed paths:

- `home.file.".pi/agent/settings.json"`
- `home.file.".pi/agent/keybindings.json"`
- `home.file.".pi/agent/prompts/<name>.md"`
- `home.file.".pi/agent/themes/<name>.json"`
- `home.file.".pi/agent/extensions/<name>.ts"`

### Generated vs sourced resources

Use a hybrid model:

- **Generated from Nix options**
  - `settings.json`
  - `keybindings.json`
- **Sourced from module-owned implementation files**
  - default prompts
  - default themes
  - default extensions
- **User overrides**
  - may be provided either as inline `text` or `source`

This keeps large Markdown/JSON/TypeScript resources maintainable without forcing everything inline into Nix.

## Module API

The module should expose a proper `programs.pi` interface.

```nix
programs.pi = {
  enable = true;
  package = pkgs.llm-agents.pi;

  settings = {
    defaultProvider = "openai-codex";
    defaultModel = "gpt-5.4";
    defaultThinkingLevel = "high";
    collapseChangelog = true;
    enableInstallTelemetry = false;
  };

  keybindings = {
    "tui.input.newLine" = [ "shift+enter" "ctrl+j" ];
  };

  prompts = {
    enable = true;
    useDefaults = true;
    disable = [ ];
    files = { };
  };

  themes = {
    enable = true;
    useDefaults = true;
    disable = [ ];
    active = "jordangarrison";
    files = { };
  };

  extensions = {
    enable = true;
    useDefaults = true;
    disable = [ ];
    files = { };
  };

  tmux = {
    enable = true;
  };
};
```

### Option semantics

#### Core options

- `enable`: turn on pi Home Manager integration
- `package`: package to install, defaulting to `pkgs.llm-agents.pi` but overridable so the caller can pass any pi derivation coming from `llm-agents.nix`
- `settings`: attrset rendered as `settings.json`
- `keybindings`: attrset rendered as `keybindings.json`

#### Resource collections

`prompts`, `themes`, and `extensions` follow the same model:

- `enable`: manage that resource class at all
- `useDefaults`: include module-owned defaults
- `disable`: remove selected default filenames
- `files`: add or replace files by filename

Each `files."<name>"` entry supports exactly one of:

- `text`
- `source`

Examples:

```nix
programs.pi.prompts.files."review.md".source = ./review.md;
```

```nix
programs.pi.prompts.files."review.md".text = ''
  ---
  description: Review staged changes
  ---
  Review the staged diff.
'';
```

## Merge behavior

### `settings`

- module defines internal defaults
- `programs.pi.settings` merges on top
- resulting attrset is serialized to `~/.pi/agent/settings.json`

### `keybindings`

- module may define minimal defaults
- `programs.pi.keybindings` merges on top
- user-provided binding keys win on conflict

### `prompts`, `themes`, `extensions`

Merge order:

1. module defaults
2. remove anything listed in `disable`
3. overlay `files`

That means `files."research.md"` replaces the default `research.md` if both exist.

### Theme activation

`programs.pi.themes.active` is the canonical way to select the active theme. The module should write:

```nix
settings.theme = programs.pi.themes.active;
```

To avoid ambiguous precedence, the module should assert that users do **not** set both:

- `programs.pi.themes.active`
- `programs.pi.settings.theme`

## Boundaries with tmux and terminals

### tmux

Pi's docs recommend:

```tmux
set -g extended-keys on
set -g extended-keys-format csi-u
```

The pi module may manage this when both are true:

- `programs.pi.tmux.enable = true`
- `programs.tmux.enable = true`

This is a small, direct UX dependency and is reasonable for the module to own.

### Terminal emulators

The pi module should **not** directly mutate Ghostty, WezTerm, or Alacritty configuration. Those belong to their own modules/config blocks.

Instead, this module should document or coordinate expected pi-friendly settings, especially because the current terminal config in this repo includes Claude-oriented `Shift+Enter` remaps that may not align with pi's preferred key handling.

## Starter defaults

The first implementation should be useful but conservative.

### Settings defaults

Seed from the current live pi config and only add clearly useful values:

- `defaultProvider`
- `defaultModel`
- `defaultThinkingLevel`
- `collapseChangelog`
- `enableInstallTelemetry`
- `treeFilterMode`
- `enableSkillCommands = true`
- `quietStartup = false`

### Keybindings defaults

Keep this minimal. A reasonable first default is:

```json
{
  "tui.input.newLine": ["shift+enter", "ctrl+j"]
}
```

This preserves normal behavior while giving a fallback in environments where modified Enter handling is imperfect.

### Prompt defaults

Ship a very small set of useful prompts:

- `research.md`
- `review.md`
- `nixos-change.md`

### Theme defaults

Ship one custom theme initially:

- `jordangarrison.json`

This should be visually aligned with the existing Rose Pine / Noctalia aesthetic already used elsewhere in the repo.

### Extension defaults

Extensions are a first-class v1 requirement. The module should ship a small default extension set that improves safety and observability without changing pi's core workflow.

Initial defaults:

- `protected-paths.ts`: prevent accidental writes to sensitive or generated paths such as `.env`, `.git/`, `node_modules/`, `.direnv/`, and `result` symlinks
- `status-line.ts`: lightweight footer/status enhancement showing useful session context without changing model/tool behavior

Reasoning:

- extension management is one of the main reasons to create this module
- defaults should prove that extension loading works end-to-end
- default extensions should be conservative and easy to disable via `programs.pi.extensions.disable`
- more invasive extensions such as plan mode, subagents, permission gates, or auto-commit can come later as explicit opt-ins

## Validation and assertions

The module should fail fast at evaluation time for bad config.

Recommended assertions:

- every `files."<name>"` entry specifies exactly one of `text` or `source`
- `programs.pi.themes.active` and `programs.pi.settings.theme` are not both set
- if `themes.active` is set, that theme exists after defaults, disables, and overrides are resolved
- disabled defaults stay disabled unless explicitly re-added via `files`
- the module never claims ownership of `auth.json`

## Integration with existing repo config

The repo already installs pi directly in `users/jordangarrison/home.nix` via `pkgs.llm-agents.pi` in `home.packages`.

Implementation should:

1. add `../../modules/home/pi` to `users/jordangarrison/home.nix` imports
2. configure `programs.pi` in `users/jordangarrison/home.nix`
3. remove the direct `llm-agents.pi` package entry from `home.packages`

Package installation should then flow through `programs.pi.package`, keeping package ownership in one place and avoiding duplicate responsibility.

## What's not included

This design does **not** include:

- project-local `.pi/settings.json` or `.pi/prompts/*` layering
- pi package publishing
- aggressive or workflow-changing default extensions
- custom provider implementation
- automatic terminal reconfiguration across Ghostty/WezTerm/Alacritty
- auth/bootstrap logic for `~/.pi/agent/auth.json`

These can be added later without redesigning the module.

## Verification

### Build-time verification

Use the repo's required `nh` invocation style and pick the command for the target configuration being changed:

```bash
# NixOS hosts with Home Manager integrated
nh os build . --no-nom

# Standalone Home Manager config, if this module is enabled there
nh home build . --no-nom

# Darwin config, if this module is enabled there
nh darwin build . --no-nom
```

### Runtime verification

After activation, verify:

1. `which pi` and `pi --version` resolve to the configured package
2. expected files exist under `~/.pi/agent/`
3. pi sees prompts/themes via startup header, `/settings`, and `/reload`
4. if tmux integration is enabled, newline handling works correctly inside tmux

### Success criteria

The first implementation is successful when:

- pi is installed via `programs.pi.package`
- stable pi config is declaratively managed through Home Manager
- prompts/themes/extensions exist and load correctly
- `auth.json` remains unmanaged and functional
- tmux support is wired when enabled
- the design leaves room for later project-local `.pi/*` layering
