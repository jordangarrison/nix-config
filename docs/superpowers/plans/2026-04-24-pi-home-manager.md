# Pi Home Manager Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `programs.pi` Home Manager module that installs pi from a configurable package, manages global pi settings/keybindings/prompts/themes/extensions under `~/.pi/agent`, and wires tmux extended-key support.

**Architecture:** Add a focused Home Manager module under `modules/home/pi/` with module-owned resources next to the module. Generate JSON files from Nix options, materialize prompt/theme/extension assets with `home.file`, keep `auth.json` unmanaged, and configure the module from `users/jordangarrison/home.nix`.

**Tech Stack:** Nix/Home Manager modules, `pkgs.formats.json`, pi prompt templates, pi TypeScript extensions, tmux Home Manager config.

---

## File Structure

Create and modify these files:

- Create: `modules/home/pi/default.nix`
  - Defines `programs.pi` options.
  - Installs `cfg.package`.
  - Generates `settings.json` and `keybindings.json`.
  - Resolves default + disabled + override resource files.
  - Writes global pi files under `.pi/agent/`.
  - Appends tmux extended-key config when enabled.

- Create: `modules/home/pi/prompts/research.md`
  - Default `/research` prompt template.

- Create: `modules/home/pi/prompts/review.md`
  - Default `/review` prompt template.

- Create: `modules/home/pi/prompts/nixos-change.md`
  - Default `/nixos-change` prompt template.

- Create: `modules/home/pi/themes/jordangarrison.json`
  - Default Rose Pine / Noctalia-inspired pi theme.

- Create: `modules/home/pi/extensions/protected-paths.ts`
  - Default conservative extension that blocks edits/writes to sensitive or generated paths.

- Create: `modules/home/pi/extensions/status-line.ts`
  - Default lightweight status-line extension.

- Modify: `users/jordangarrison/home.nix`
  - Import `../../modules/home/pi`.
  - Configure `programs.pi` with `package = pkgs.llm-agents.pi`.
  - Remove direct `llm-agents.pi` from `home.packages`.

---

### Task 1: Add module-owned pi resources

**Files:**
- Create: `modules/home/pi/prompts/research.md`
- Create: `modules/home/pi/prompts/review.md`
- Create: `modules/home/pi/prompts/nixos-change.md`
- Create: `modules/home/pi/themes/jordangarrison.json`
- Create: `modules/home/pi/extensions/protected-paths.ts`
- Create: `modules/home/pi/extensions/status-line.ts`

- [ ] **Step 1: Create the pi resource directories**

Run:

```bash
mkdir -p modules/home/pi/prompts modules/home/pi/themes modules/home/pi/extensions
```

Expected: command exits successfully and creates the directories.

- [ ] **Step 2: Create the research prompt**

Write `modules/home/pi/prompts/research.md` with:

```markdown
---
description: Research a topic before planning or implementing
argument-hint: "<topic>"
---
Research `$ARGUMENTS` thoroughly before proposing changes.

Start with local context:

1. Read relevant project documentation and agent guidance.
2. Inspect existing files and patterns before suggesting implementation.
3. Identify constraints, conventions, risks, and open questions.
4. Summarize findings with concrete file paths and recommended next steps.

Do not modify files during research unless explicitly asked.
```

- [ ] **Step 3: Create the review prompt**

Write `modules/home/pi/prompts/review.md` with:

```markdown
---
description: Review current repository changes for correctness and risk
argument-hint: "[focus]"
---
Review the current repository changes. Focus on `$ARGUMENTS` if provided.

Use git and local inspection to check:

1. Changed files and unstaged/staged diffs.
2. Correctness and regressions.
3. Security, secrets, and unsafe filesystem behavior.
4. Nix/Home Manager evaluation risks.
5. Missing verification commands.

Report findings as:

- **Blocking**: must fix before merge
- **Non-blocking**: improvement or follow-up
- **Looks good**: areas checked with no findings

Do not modify files unless explicitly asked.
```

- [ ] **Step 4: Create the NixOS change prompt**

Write `modules/home/pi/prompts/nixos-change.md` with:

```markdown
---
description: Make a NixOS/Home Manager change using this repo's conventions
argument-hint: "<change>"
---
Make this NixOS/Home Manager change: `$ARGUMENTS`.

Follow this repository's conventions:

1. Read `AGENTS.md` and any relevant module-specific guidance.
2. Prefer module-based implementations under `modules/`.
3. Use existing patterns before introducing new abstractions.
4. Keep secrets and mutable auth files out of Nix-managed files.
5. Use `nh` with `--no-nom` for verification.

For NixOS hosts, build first:

```bash
nh os build . --no-nom
```

For standalone Home Manager changes, build with:

```bash
nh home build . --no-nom
```

Do not run switch commands unless explicitly asked.
```

- [ ] **Step 5: Create the pi theme**

Write `modules/home/pi/themes/jordangarrison.json` with:

```json
{
  "$schema": "https://raw.githubusercontent.com/badlogic/pi-mono/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json",
  "name": "jordangarrison",
  "vars": {
    "base": "#191724",
    "surface": "#1f1d2e",
    "overlay": "#26233a",
    "muted": "#6e6a86",
    "subtle": "#908caa",
    "text": "#e0def4",
    "love": "#eb6f92",
    "gold": "#f6c177",
    "rose": "#ebbcba",
    "pine": "#31748f",
    "foam": "#9ccfd8",
    "iris": "#c4a7e7",
    "highlightLow": "#21202e",
    "highlightMed": "#403d52",
    "highlightHigh": "#524f67"
  },
  "colors": {
    "accent": "iris",
    "border": "highlightMed",
    "borderAccent": "iris",
    "borderMuted": "overlay",
    "success": "foam",
    "error": "love",
    "warning": "gold",
    "muted": "subtle",
    "dim": "muted",
    "text": "text",
    "thinkingText": "subtle",
    "selectedBg": "overlay",
    "userMessageBg": "surface",
    "userMessageText": "text",
    "customMessageBg": "surface",
    "customMessageText": "text",
    "customMessageLabel": "rose",
    "toolPendingBg": "highlightLow",
    "toolSuccessBg": "#1d2e2d",
    "toolErrorBg": "#2d1f2a",
    "toolTitle": "foam",
    "toolOutput": "text",
    "mdHeading": "rose",
    "mdLink": "foam",
    "mdLinkUrl": "subtle",
    "mdCode": "gold",
    "mdCodeBlock": "text",
    "mdCodeBlockBorder": "highlightMed",
    "mdQuote": "subtle",
    "mdQuoteBorder": "highlightMed",
    "mdHr": "highlightMed",
    "mdListBullet": "iris",
    "toolDiffAdded": "foam",
    "toolDiffRemoved": "love",
    "toolDiffContext": "subtle",
    "syntaxComment": "muted",
    "syntaxKeyword": "iris",
    "syntaxFunction": "foam",
    "syntaxVariable": "rose",
    "syntaxString": "gold",
    "syntaxNumber": "love",
    "syntaxType": "pine",
    "syntaxOperator": "iris",
    "syntaxPunctuation": "subtle",
    "thinkingOff": "muted",
    "thinkingMinimal": "subtle",
    "thinkingLow": "pine",
    "thinkingMedium": "foam",
    "thinkingHigh": "iris",
    "thinkingXhigh": "love",
    "bashMode": "gold"
  },
  "export": {
    "pageBg": "#191724",
    "cardBg": "#1f1d2e",
    "infoBg": "#26233a"
  }
}
```

- [ ] **Step 6: Create the protected paths extension**

Write `modules/home/pi/extensions/protected-paths.ts` with:

```typescript
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const protectedPathSegments = new Set([".git", "node_modules", ".direnv"]);
const protectedBasenames = new Set(["result", "result-1", "result-2"]);

function normalizePath(path: string): string {
  return path.replaceAll("\\", "/");
}

function basename(path: string): string {
  const normalized = normalizePath(path).replace(/\/+$/, "");
  const parts = normalized.split("/").filter(Boolean);
  return parts[parts.length - 1] ?? normalized;
}

function isEnvFile(path: string): boolean {
  const name = basename(path);
  return name === ".env" || name.startsWith(".env.");
}

function hasProtectedSegment(path: string): boolean {
  const segments = normalizePath(path).split("/").filter(Boolean);
  return segments.some((segment) => protectedPathSegments.has(segment));
}

function isProtectedPath(path: string): boolean {
  return isEnvFile(path) || hasProtectedSegment(path) || protectedBasenames.has(basename(path));
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "write" && event.toolName !== "edit") {
      return undefined;
    }

    const path = event.input.path;
    if (typeof path !== "string") {
      return undefined;
    }

    if (!isProtectedPath(path)) {
      return undefined;
    }

    if (ctx.hasUI) {
      ctx.ui.notify(`Blocked ${event.toolName} to protected path: ${path}`, "warning");
    }

    return {
      block: true,
      reason: `Path "${path}" is protected by the protected-paths extension`,
    };
  });
}
```

- [ ] **Step 7: Create the status line extension**

Write `modules/home/pi/extensions/status-line.ts` with:

```typescript
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  let turnCount = 0;

  pi.on("session_start", async (_event, ctx) => {
    if (!ctx.hasUI) return;
    ctx.ui.setStatus("jordangarrison-status", ctx.ui.theme.fg("dim", "pi ready"));
  });

  pi.on("turn_start", async (_event, ctx) => {
    if (!ctx.hasUI) return;
    turnCount += 1;
    const marker = ctx.ui.theme.fg("accent", "●");
    const label = ctx.ui.theme.fg("dim", ` turn ${turnCount}`);
    ctx.ui.setStatus("jordangarrison-status", `${marker}${label}`);
  });

  pi.on("turn_end", async (_event, ctx) => {
    if (!ctx.hasUI) return;
    const marker = ctx.ui.theme.fg("success", "✓");
    const label = ctx.ui.theme.fg("dim", ` turn ${turnCount} complete`);
    ctx.ui.setStatus("jordangarrison-status", `${marker}${label}`);
  });
}
```

- [ ] **Step 8: Commit the resource files**

Run:

```bash
git add modules/home/pi/prompts modules/home/pi/themes modules/home/pi/extensions
git commit -m "feat(pi): add default prompts theme and extensions"
```

Expected: commit succeeds and includes only the new resource files.

---

### Task 2: Implement the `programs.pi` Home Manager module

**Files:**
- Create: `modules/home/pi/default.nix`

- [ ] **Step 1: Write the module implementation**

Write `modules/home/pi/default.nix` with:

```nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.pi;
  jsonFormat = pkgs.formats.json { };

  fileEntryType = types.submodule {
    options = {
      text = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "Inline file contents to write.";
      };

      source = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Source file to link into the pi agent directory.";
      };
    };
  };

  resourceOptions = kind: {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to manage pi ${kind}.";
    };

    useDefaults = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to include the module-provided default pi ${kind}.";
    };

    disable = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Default pi ${kind} filenames to omit.";
    };

    files = mkOption {
      type = types.attrsOf fileEntryType;
      default = { };
      description = "Additional or replacement pi ${kind} files keyed by filename.";
    };
  };

  defaultSettings = {
    defaultProvider = "openai-codex";
    defaultModel = "gpt-5.4";
    defaultThinkingLevel = "high";
    collapseChangelog = true;
    enableInstallTelemetry = false;
    enableSkillCommands = true;
    quietStartup = false;
    treeFilterMode = "default";
  };

  defaultKeybindings = {
    "tui.input.newLine" = [
      "shift+enter"
      "ctrl+j"
    ];
  };

  defaultPrompts = {
    "research.md".source = ./prompts/research.md;
    "review.md".source = ./prompts/review.md;
    "nixos-change.md".source = ./prompts/nixos-change.md;
  };

  defaultThemes = {
    "jordangarrison.json".source = ./themes/jordangarrison.json;
  };

  defaultExtensions = {
    "protected-paths.ts".source = ./extensions/protected-paths.ts;
    "status-line.ts".source = ./extensions/status-line.ts;
  };

  resolveResources = defaults: resourceCfg:
    if !resourceCfg.enable then
      { }
    else
      (if resourceCfg.useDefaults then removeAttrs defaults resourceCfg.disable else { })
      // resourceCfg.files;

  promptFiles = resolveResources defaultPrompts cfg.prompts;
  themeFiles = resolveResources defaultThemes cfg.themes;
  extensionFiles = resolveResources defaultExtensions cfg.extensions;

  fileToHomeFile = directory: name: file:
    nameValuePair ".pi/agent/${directory}/${name}"
      (if file.text != null then { inherit (file) text; } else { inherit (file) source; });

  resourceHomeFiles = directory: files:
    listToAttrs (mapAttrsToList (fileToHomeFile directory) files);

  settingsWithTheme =
    recursiveUpdate defaultSettings cfg.settings
    // optionalAttrs (cfg.themes.enable && cfg.themes.active != null) {
      theme = cfg.themes.active;
    };

  keybindings = recursiveUpdate defaultKeybindings cfg.keybindings;

  settingsFile = jsonFormat.generate "pi-settings.json" settingsWithTheme;
  keybindingsFile = jsonFormat.generate "pi-keybindings.json" keybindings;

  fileEntryAssertions = kind: files:
    mapAttrsToList (name: file: {
      assertion = (file.text != null) != (file.source != null);
      message = "programs.pi.${kind}.files.${name} must set exactly one of text or source.";
    }) files;

  activeThemeFile =
    if cfg.themes.active == null then null else "${cfg.themes.active}.json";
in
{
  options.programs.pi = {
    enable = mkEnableOption "pi coding agent";

    package = mkOption {
      type = types.package;
      default = pkgs.llm-agents.pi;
      defaultText = literalExpression "pkgs.llm-agents.pi";
      description = "The pi package to install.";
    };

    settings = mkOption {
      type = jsonFormat.type;
      default = { };
      description = "Settings written to ~/.pi/agent/settings.json.";
    };

    keybindings = mkOption {
      type = jsonFormat.type;
      default = { };
      description = "Keybindings written to ~/.pi/agent/keybindings.json.";
    };

    prompts = mkOption {
      type = types.submodule {
        options = resourceOptions "prompt templates";
      };
      default = { };
      description = "Prompt template files written to ~/.pi/agent/prompts/.";
    };

    themes = mkOption {
      type = types.submodule {
        options = resourceOptions "themes" // {
          active = mkOption {
            type = types.nullOr types.str;
            default = "jordangarrison";
            description = ''
              Active pi theme name. When set, this module writes the value to
              settings.theme and expects a managed theme file named <active>.json.
            '';
          };
        };
      };
      default = { };
      description = "Theme files written to ~/.pi/agent/themes/.";
    };

    extensions = mkOption {
      type = types.submodule {
        options = resourceOptions "extensions";
      };
      default = { };
      description = "Extension files written to ~/.pi/agent/extensions/.";
    };

    tmux = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to add pi-friendly tmux extended key settings when tmux is enabled.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions =
      fileEntryAssertions "prompts" cfg.prompts.files
      ++ fileEntryAssertions "themes" cfg.themes.files
      ++ fileEntryAssertions "extensions" cfg.extensions.files
      ++ [
        {
          assertion = !(cfg.themes.enable && cfg.themes.active != null && cfg.settings ? theme);
          message = "Set programs.pi.themes.active or programs.pi.settings.theme, not both.";
        }
        {
          assertion =
            !(cfg.themes.enable && cfg.themes.active != null)
            || hasAttr activeThemeFile themeFiles;
          message = "programs.pi.themes.active is '${cfg.themes.active}', but no managed theme file named '${activeThemeFile}' exists.";
        }
      ];

    home.packages = [ cfg.package ];

    home.file = {
      ".pi/agent/settings.json".source = settingsFile;
      ".pi/agent/keybindings.json".source = keybindingsFile;
    }
    // resourceHomeFiles "prompts" promptFiles
    // resourceHomeFiles "themes" themeFiles
    // resourceHomeFiles "extensions" extensionFiles;

    programs.tmux.extraConfig = mkIf (cfg.tmux.enable && config.programs.tmux.enable) (mkAfter ''
      set -g extended-keys on
      set -g extended-keys-format csi-u
    '');
  };
}
```

- [ ] **Step 2: Format the module**

Run:

```bash
nixfmt modules/home/pi/default.nix
```

Expected: command exits successfully and rewrites the file in standard Nix style.

- [ ] **Step 3: Evaluate the standalone Home Manager configuration**

Run:

```bash
nix eval .#homeConfigurations."jordangarrison@normandy".activationPackage.drvPath --show-trace
```

Expected: command prints a derivation path or fails only because the module is not imported yet. If it fails due to syntax or option errors in `modules/home/pi/default.nix`, fix the module before continuing.

- [ ] **Step 4: Commit the module**

Run:

```bash
git add modules/home/pi/default.nix
git commit -m "feat(pi): add Home Manager module"
```

Expected: commit succeeds and includes only `modules/home/pi/default.nix`.

---

### Task 3: Wire the pi module into Jordan's Home Manager config

**Files:**
- Modify: `users/jordangarrison/home.nix`

- [ ] **Step 1: Add the pi module import**

In `users/jordangarrison/home.nix`, change the imports block from:

```nix
  imports = [
    ./tools/nvim/nvf.nix
    ../../modules/home/languages
  ];
```

to:

```nix
  imports = [
    ./tools/nvim/nvf.nix
    ../../modules/home/languages
    ../../modules/home/pi
  ];
```

- [ ] **Step 2: Remove direct pi package installation**

In `users/jordangarrison/home.nix`, remove this entry from `home.packages`:

```nix
      llm-agents.pi
```

Keep the surrounding LLM agent packages:

```nix
      llm-agents.claude-code
      llm-agents.codex
      llm-agents.opencode
```

- [ ] **Step 3: Configure `programs.pi`**

Add this block immediately after `programs.home-manager.enable = true;` in `users/jordangarrison/home.nix`:

```nix
  programs.pi = {
    enable = true;
    package = pkgs.llm-agents.pi;
  };
```

This uses module defaults for settings, keybindings, prompts, themes, extensions, and tmux.

- [ ] **Step 4: Format the modified file**

Run:

```bash
nixfmt users/jordangarrison/home.nix
```

Expected: command exits successfully.

- [ ] **Step 5: Evaluate the standalone Home Manager configuration**

Run:

```bash
nix eval .#homeConfigurations."jordangarrison@normandy".activationPackage.drvPath --show-trace
```

Expected: command prints a derivation path. If it reports `programs.pi` option errors, fix `modules/home/pi/default.nix` or the `programs.pi` config before continuing.

- [ ] **Step 6: Commit the wiring change**

Run:

```bash
git add users/jordangarrison/home.nix
git commit -m "feat(pi): enable declarative user config"
```

Expected: commit succeeds and includes only `users/jordangarrison/home.nix`.

---

### Task 4: Verify generated pi files through Home Manager build

**Files:**
- No source files changed unless verification finds a defect.

- [ ] **Step 1: Build the standalone Home Manager config**

Run:

```bash
nh home build . --no-nom
```

Expected: build completes successfully. If this fails because `nh home build .` targets a different local configuration than `jordangarrison@normandy`, run the explicit flake build in Step 2.

- [ ] **Step 2: Build the explicit standalone activation package**

Run:

```bash
nix build .#homeConfigurations."jordangarrison@normandy".activationPackage --show-trace
```

Expected: build completes successfully and creates a `result` symlink in the repository root.

- [ ] **Step 3: Inspect the generated Home Manager files in the build output**

Run:

```bash
find result -path '*home-files/.pi/agent/*' -type l -o -path '*home-files/.pi/agent/*' -type f | sort
```

Expected output includes paths ending in:

```text
.pi/agent/extensions/protected-paths.ts
.pi/agent/extensions/status-line.ts
.pi/agent/keybindings.json
.pi/agent/prompts/nixos-change.md
.pi/agent/prompts/research.md
.pi/agent/prompts/review.md
.pi/agent/settings.json
.pi/agent/themes/jordangarrison.json
```

- [ ] **Step 4: Inspect generated settings JSON**

Run:

```bash
python -m json.tool result/home-files/.pi/agent/settings.json
```

Expected JSON includes:

```json
{
  "collapseChangelog": true,
  "defaultModel": "gpt-5.4",
  "defaultProvider": "openai-codex",
  "defaultThinkingLevel": "high",
  "enableInstallTelemetry": false,
  "enableSkillCommands": true,
  "quietStartup": false,
  "theme": "jordangarrison",
  "treeFilterMode": "default"
}
```

- [ ] **Step 5: Inspect generated keybindings JSON**

Run:

```bash
python -m json.tool result/home-files/.pi/agent/keybindings.json
```

Expected JSON includes:

```json
{
  "tui.input.newLine": [
    "shift+enter",
    "ctrl+j"
  ]
}
```

- [ ] **Step 6: Build the active NixOS host config**

Run:

```bash
nh os build . --no-nom
```

Expected: build completes successfully on a NixOS host. If running from a non-NixOS environment, record that this step was skipped because `nh os build` is not applicable in that environment.

- [ ] **Step 7: Commit verification fixes if needed**

If any verification step required source fixes, run:

```bash
git add modules/home/pi users/jordangarrison/home.nix
git commit -m "fix(pi): correct generated Home Manager files"
```

Expected: commit succeeds only if source fixes were made. If no fixes were made, do not create a commit for this step.

---

### Task 5: Runtime smoke test after activation

**Files:**
- No source files changed unless runtime verification finds a defect.

- [ ] **Step 1: Apply Home Manager or NixOS test activation only after builds pass**

On NixOS, run:

```bash
nh os test . --no-nom
```

Expected: activation test completes successfully without switching the booted generation.

For standalone Home Manager, run:

```bash
nh home switch . --no-nom
```

Expected: Home Manager activation completes successfully.

- [ ] **Step 2: Confirm pi binary path**

Run:

```bash
which pi
readlink -f "$(which pi)"
```

Expected: output resolves through the Home Manager profile to a Nix store path for `pi` from `pkgs.llm-agents.pi`.

- [ ] **Step 3: Confirm managed pi files exist**

Run:

```bash
find ~/.pi/agent -maxdepth 3 -type f | sort | grep -E 'settings.json|keybindings.json|prompts/|themes/|extensions/'
```

Expected output includes:

```text
/home/jordangarrison/.pi/agent/extensions/protected-paths.ts
/home/jordangarrison/.pi/agent/extensions/status-line.ts
/home/jordangarrison/.pi/agent/keybindings.json
/home/jordangarrison/.pi/agent/prompts/nixos-change.md
/home/jordangarrison/.pi/agent/prompts/research.md
/home/jordangarrison/.pi/agent/prompts/review.md
/home/jordangarrison/.pi/agent/settings.json
/home/jordangarrison/.pi/agent/themes/jordangarrison.json
```

- [ ] **Step 4: Confirm auth remains unmanaged**

Run:

```bash
home-manager generations >/dev/null
ls -l ~/.pi/agent/auth.json
```

Expected: `~/.pi/agent/auth.json` exists if pi auth was already configured, and it is not a Home Manager symlink into the Nix store.

- [ ] **Step 5: Start pi and reload resources**

Run:

```bash
pi
```

Inside pi, run:

```text
/reload
/settings
/hotkeys
```

Expected:

- startup or settings show the `jordangarrison` theme
- `/research`, `/review`, and `/nixos-change` appear as prompt templates
- no extension load errors appear
- `Ctrl+J` and `Shift+Enter` both create new lines where the terminal supports the modified key event

- [ ] **Step 6: Commit runtime fixes if needed**

If runtime testing required source fixes, run:

```bash
git add modules/home/pi users/jordangarrison/home.nix
git commit -m "fix(pi): correct runtime resource loading"
```

Expected: commit succeeds only if source fixes were made. If no fixes were made, do not create a commit for this step.

---

## Plan Self-Review

### Spec coverage

- Configurable `programs.pi.package`: Task 2 and Task 3.
- Generated `settings.json` and `keybindings.json`: Task 2 and Task 4.
- Prompts, themes, and extensions under `~/.pi/agent`: Task 1, Task 2, and Task 4.
- Extensions as v1 requirement: Task 1 creates `protected-paths.ts` and `status-line.ts`; Task 4 verifies they are generated; Task 5 verifies they load.
- `auth.json` unmanaged: Task 2 does not define it; Task 5 verifies it is not Home Manager-owned.
- tmux extended-key support: Task 2 implements it.
- Existing direct package entry removed: Task 3.
- Verification with `--no-nom`: Task 4 and Task 5.

### Placeholder scan

This plan contains complete file contents for each created file, exact edit locations for existing files, exact commands, expected outcomes, and no deferred implementation sections.

### Type consistency

The plan consistently uses:

- `programs.pi.settings`
- `programs.pi.keybindings`
- `programs.pi.prompts`
- `programs.pi.themes`
- `programs.pi.extensions`
- `programs.pi.tmux.enable`
- `files.<name>.text`
- `files.<name>.source`
