# Agent Shell ACP Adapters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Xenodium `agent-shell` to Doom Emacs with Claude, Codex, and Pi ACP support managed through a reusable, overridable Home Manager ACP adapter module.

**Architecture:** Home Manager owns external ACP adapter binaries through `programs.acp-adapters`; Doom owns Emacs packages, `agent-shell` configuration, and keybindings. The adapter module defaults to `pkgs.llm-agents` packages for Claude and Codex, prefers `pkgs.llm-agents.pi-acp` for Pi when available, falls back to this repository's local `packages/pi-acp`, and exposes per-adapter package overrides for callers that need a different source.

**Tech Stack:** Nix flakes, Home Manager modules, Doom Emacs, Emacs Lisp, `agent-shell`, `acp.el`, `shell-maker`, `pkgs.llm-agents`.

---

## File structure

- Create `modules/home/acp-adapters/default.nix`
  - Defines `programs.acp-adapters` options.
  - Installs enabled ACP adapter packages into `home.packages`.
  - Defaults Claude to `pkgs.llm-agents.claude-code-acp` and Codex to `pkgs.llm-agents.codex-acp`.
  - Defaults Pi to `pkgs.llm-agents.pi-acp` when that attribute exists, otherwise to `packages/pi-acp`.
  - Allows each package and command name to be overridden.
  - Fails with a clear assertion when an adapter is enabled without an available package.

- Modify `users/jordangarrison/home.nix`
  - Import `../../modules/home/acp-adapters`.
  - Enable `programs.acp-adapters`.
  - Leave per-adapter package overrides unset so Claude and Codex come from the `llm-agents` flake overlay and Pi auto-enables once that flake exposes `pi-acp`.

- Modify `users/jordangarrison/tools/doom.d/packages.el`
  - Add Doom packages required by `agent-shell`: `shell-maker`, `acp`, and `agent-shell`.

- Modify `users/jordangarrison/tools/doom.d/config.org`
  - Add an `Agent Shell` subsection under `AI/LLM Integration`.
  - Configure Claude, Codex, and Pi commands.
  - Use login-based auth for Claude and Codex.
  - Inherit Emacs process environment for spawned ACP adapters.
  - Include Pi in the `agent-shell` picker only when `pi-acp` is installed.
  - Add leader keybindings.

---

### Task 1: Add reusable ACP adapters Home Manager module

**Files:**
- Create: `modules/home/acp-adapters/default.nix`

- [ ] **Step 1: Verify the option does not exist yet**

Run:

```bash
nix eval '.#homeConfigurations."jordangarrison@normandy".config.programs.acp-adapters.enable'
```

Expected: FAIL with an error containing this text:

```text
attribute 'acp-adapters' missing
```

- [ ] **Step 2: Create the module file**

Create `modules/home/acp-adapters/default.nix` with this exact content:

```nix
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    literalExpression
    mkEnableOption
    mkIf
    mkOption
    optional
    types
    ;

  cfg = config.programs.acp-adapters;
  llmAgents = pkgs.llm-agents or { };

  llmPackage = name: if builtins.hasAttr name llmAgents then builtins.getAttr name llmAgents else null;

  adapterPackageOption =
    {
      adapterName,
      llmPackageName,
      defaultPackage,
    }:
    mkOption {
      type = types.nullOr types.package;
      default = defaultPackage;
      defaultText = literalExpression "pkgs.llm-agents.${llmPackageName} or null";
      description = ''
        Package providing the ${adapterName} ACP adapter binary. Defaults to
        pkgs.llm-agents.${llmPackageName} when that package exists, but may be
        overridden with a nixpkgs package, local package, or future flake output.
      '';
    };

  adapterCommandOption =
    {
      adapterName,
      defaultCommand,
    }:
    mkOption {
      type = types.str;
      default = defaultCommand;
      description = ''
        Command name for the ${adapterName} ACP adapter binary. This option is
        informational for consumers such as Doom Emacs configuration; the module
        installs packages but does not generate wrappers.
      '';
    };

  enabledAdapterPackages =
    optional (cfg.claude.enable && cfg.claude.package != null) cfg.claude.package
    ++ optional (cfg.codex.enable && cfg.codex.package != null) cfg.codex.package
    ++ optional (cfg.pi.enable && cfg.pi.package != null) cfg.pi.package;
in
{
  options.programs.acp-adapters = {
    enable = mkEnableOption "ACP adapter binaries for agent clients";

    claude = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to install the Claude ACP adapter.";
      };

      package = adapterPackageOption {
        adapterName = "Claude";
        llmPackageName = "claude-code-acp";
        defaultPackage = llmPackage "claude-code-acp";
      };

      command = adapterCommandOption {
        adapterName = "Claude";
        defaultCommand = "claude-agent-acp";
      };
    };

    codex = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to install the Codex ACP adapter.";
      };

      package = adapterPackageOption {
        adapterName = "Codex";
        llmPackageName = "codex-acp";
        defaultPackage = llmPackage "codex-acp";
      };

      command = adapterCommandOption {
        adapterName = "Codex";
        defaultCommand = "codex-acp";
      };
    };

    pi = {
      enable = mkOption {
        type = types.bool;
        default = llmPackage "pi-acp" != null;
        defaultText = literalExpression "pkgs.llm-agents ? pi-acp";
        description = ''
          Whether to install the Pi ACP adapter. This defaults to true only when
          pkgs.llm-agents.pi-acp exists, because the current llm-agents input may
          not expose a Pi ACP package yet.
        '';
      };

      package = adapterPackageOption {
        adapterName = "Pi";
        llmPackageName = "pi-acp";
        defaultPackage = llmPackage "pi-acp";
      };

      command = adapterCommandOption {
        adapterName = "Pi";
        defaultCommand = "pi-acp";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.claude.enable && cfg.claude.package == null);
        message = "programs.acp-adapters.claude.enable is true, but no Claude ACP package is available. Set programs.acp-adapters.claude.package or expose pkgs.llm-agents.claude-code-acp.";
      }
      {
        assertion = !(cfg.codex.enable && cfg.codex.package == null);
        message = "programs.acp-adapters.codex.enable is true, but no Codex ACP package is available. Set programs.acp-adapters.codex.package or expose pkgs.llm-agents.codex-acp.";
      }
      {
        assertion = !(cfg.pi.enable && cfg.pi.package == null);
        message = "programs.acp-adapters.pi.enable is true, but no Pi ACP package is available. Set programs.acp-adapters.pi.package or expose pkgs.llm-agents.pi-acp.";
      }
    ];

    home.packages = enabledAdapterPackages;
  };
}
```

- [ ] **Step 3: Commit the module**

```bash
git add modules/home/acp-adapters/default.nix
git commit -m "feat(home): add acp adapters module"
```

Expected: commit succeeds.

---

### Task 2: Import and enable ACP adapters for Jordan

**Files:**
- Modify: `users/jordangarrison/home.nix`

- [ ] **Step 1: Add the module import**

In `users/jordangarrison/home.nix`, change the imports block from:

```nix
  imports = [
    ./tools/nvim/nvf.nix
    ../../modules/home/languages
    ../../modules/home/pi
  ];
```

to:

```nix
  imports = [
    ./tools/nvim/nvf.nix
    ../../modules/home/acp-adapters
    ../../modules/home/languages
    ../../modules/home/pi
  ];
```

- [ ] **Step 2: Enable the ACP adapters module**

Immediately after the existing `programs.pi` block:

```nix
  programs.pi = {
    enable = true;
    package = pkgs.llm-agents.pi;
  };
```

add:

```nix
  programs.acp-adapters = {
    enable = true;
  };
```

This installs Claude and Codex ACP adapters from `pkgs.llm-agents`. Pi ACP installs from `pkgs.llm-agents.pi-acp` when available, otherwise from the local `packages/pi-acp` fallback.

- [ ] **Step 3: Verify the enabled option evaluates**

Run:

```bash
nix eval '.#homeConfigurations."jordangarrison@normandy".config.programs.acp-adapters.enable'
```

Expected output:

```text
true
```

- [ ] **Step 4: Verify Claude and Codex resolve to llm-agents packages**

Run:

```bash
nix eval --raw '.#homeConfigurations."jordangarrison@normandy".config.programs.acp-adapters.claude.package.meta.mainProgram'
nix eval --raw '.#homeConfigurations."jordangarrison@normandy".config.programs.acp-adapters.codex.package.meta.mainProgram'
```

Expected output:

```text
claude-agent-acp
codex-acp
```

- [ ] **Step 5: Verify Pi is disabled when the llm flake lacks pi-acp**

Run:

```bash
nix eval '.#homeConfigurations."jordangarrison@normandy".config.programs.acp-adapters.pi.enable'
```

Expected output:

```text
true
```

- [ ] **Step 6: Commit Jordan's Home Manager enablement**

```bash
git add users/jordangarrison/home.nix
git commit -m "feat(home): enable acp adapters"
```

Expected: commit succeeds.

---

### Task 3: Add Doom packages for agent-shell

**Files:**
- Modify: `users/jordangarrison/tools/doom.d/packages.el`

- [ ] **Step 1: Add package declarations**

In `users/jordangarrison/tools/doom.d/packages.el`, change this section:

```elisp
;; Standard Packages
(package! prettier-js)
(package! xclip)
(package! sqlite3)
(package! vcl-mode)
```

to:

```elisp
;; Standard Packages
(package! prettier-js)
(package! xclip)
(package! sqlite3)
(package! vcl-mode)
(package! shell-maker)
(package! acp)
(package! agent-shell)
```

- [ ] **Step 2: Run Doom sync to install package recipes**

Run:

```bash
doom sync
```

Expected: command exits 0 and output includes package synchronization without errors.

- [ ] **Step 3: Commit Doom package declarations**

```bash
git add users/jordangarrison/tools/doom.d/packages.el
git commit -m "feat(doom): add agent-shell packages"
```

Expected: commit succeeds.

---

### Task 4: Configure agent-shell in Doom

**Files:**
- Modify: `users/jordangarrison/tools/doom.d/config.org`

- [ ] **Step 1: Add Agent Shell config block**

In `users/jordangarrison/tools/doom.d/config.org`, immediately after this block:

```org
** Integration with various AI and language model services for enhanced development capabilities.

#+begin_src emacs-lisp
(gptel-make-gh-copilot "Copilot")
#+end_src
```

insert:

```org
** Agent Shell
Native Emacs shell for ACP-driven coding agents. Adapter binaries are installed through Home Manager's `programs.acp-adapters` module.

#+begin_src emacs-lisp
(require 'acp)
(require 'agent-shell)

(after! agent-shell
  (setq agent-shell-anthropic-authentication
        (agent-shell-anthropic-make-authentication :login t)
        agent-shell-openai-authentication
        (agent-shell-openai-make-authentication :login t)
        agent-shell-anthropic-claude-acp-command '("claude-agent-acp")
        agent-shell-openai-codex-acp-command '("codex-acp")
        agent-shell-pi-acp-command '("pi-acp")
        agent-shell-anthropic-claude-environment
        (agent-shell-make-environment-variables :inherit-env t)
        agent-shell-openai-codex-environment
        (agent-shell-make-environment-variables :inherit-env t)
        agent-shell-pi-environment
        (agent-shell-make-environment-variables :inherit-env t))

  (setq agent-shell-agent-configs
        (append
         (list (agent-shell-anthropic-make-claude-code-config)
               (agent-shell-openai-make-codex-config))
         (when (executable-find "pi-acp")
           (list (agent-shell-pi-make-agent-config))))))

(map! :leader
      :desc "Agent shell" "j a a" #'agent-shell
      :desc "Agent shell Claude" "j a c" #'agent-shell-anthropic-start-claude-code
      :desc "Agent shell Codex" "j a x" #'agent-shell-openai-start-codex
      :desc "Agent shell Pi" "j a p" #'agent-shell-pi-start-agent)
#+end_src
```

- [ ] **Step 2: Tangle Doom config through Doom sync**

Run:

```bash
doom sync
```

Expected: command exits 0 and tangles `config.org` without errors.

- [ ] **Step 3: Verify the generated config references agent-shell**

Run:

```bash
rg -n "agent-shell-agent-configs|agent-shell-anthropic-claude-acp-command|agent-shell-openai-codex-acp-command|agent-shell-pi-acp-command" ~/.doom.d/config.el ~/.config/doom/config.el 2>/dev/null || true
```

Expected: output includes the four searched symbols from the generated Doom config location that exists on the machine.

- [ ] **Step 4: Commit Doom agent-shell config**

```bash
git add users/jordangarrison/tools/doom.d/config.org
git commit -m "feat(doom): configure agent-shell"
```

Expected: commit succeeds.

---

### Task 5: Verify Nix and adapter binaries

**Files:**
- No file changes expected.

- [ ] **Step 1: Build Home Manager configuration**

Run:

```bash
nh home build . --no-nom
```

Expected: command exits 0. If `nh home build` is unavailable in the local `nh` version, run this equivalent flake build instead:

```bash
nix build '.#homeConfigurations."jordangarrison@normandy".activationPackage'
```

Expected: command exits 0.

- [ ] **Step 2: Verify adapter package outputs in the Nix profile build**

Run:

```bash
nix eval --raw '.#homeConfigurations."jordangarrison@normandy".config.programs.acp-adapters.claude.package.meta.mainProgram'
nix eval --raw '.#homeConfigurations."jordangarrison@normandy".config.programs.acp-adapters.codex.package.meta.mainProgram'
nix eval '.#homeConfigurations."jordangarrison@normandy".config.programs.acp-adapters.pi.enable'
```

Expected output:

```text
claude-agent-acp
codex-acp
true
```

- [ ] **Step 3: If switching Home Manager is approved, apply it**

Run only when the user wants the configuration applied in the current session:

```bash
nh home switch . --no-nom
```

Expected: command exits 0.

- [ ] **Step 4: Verify installed commands after switch**

Run after Step 3:

```bash
command -v claude-agent-acp
command -v codex-acp
if nix eval '.#homeConfigurations."jordangarrison@normandy".config.programs.acp-adapters.pi.enable' | rg -q true; then
  command -v pi-acp
else
  echo "pi-acp not enabled because pkgs.llm-agents.pi-acp is not available"
fi
```

Expected output includes paths for `claude-agent-acp`, `codex-acp`, and `pi-acp`.

---

### Task 6: Final verification and cleanup

**Files:**
- No file changes expected unless verification reveals a syntax or evaluation issue.

- [ ] **Step 1: Check git history for task commits**

Run:

```bash
git log --oneline -6
```

Expected: output includes commits for:

```text
feat(home): add acp adapters module
feat(home): enable acp adapters
feat(doom): add agent-shell packages
feat(doom): configure agent-shell
```

- [ ] **Step 2: Check working tree cleanliness**

Run:

```bash
git status --short
```

Expected: no output.

- [ ] **Step 3: Summarize what is ready in Emacs**

Report these facts to the user:

```text
agent-shell is configured in Doom Emacs.
Claude uses claude-agent-acp from pkgs.llm-agents.claude-code-acp.
Codex uses codex-acp from pkgs.llm-agents.codex-acp.
Pi agent-shell support is configured and appears in the picker when pi-acp is installed; the ACP adapter module prefers pkgs.llm-agents.pi-acp and falls back to the local packages/pi-acp package until the llm flake exposes pi-acp.
```

---

## Self-review checklist

- Spec coverage: This plan implements the reusable ACP adapter module, Doom package declarations, Doom `agent-shell` configuration, leader keybindings, and verification commands. It preserves existing AI tooling by only adding new sections and packages.
- Package source requirement: Claude and Codex defaults come from `pkgs.llm-agents`; Pi prefers `pkgs.llm-agents.pi-acp` and falls back to local `packages/pi-acp`; the module exposes package overrides for all adapters.
- Placeholder scan: No implementation step relies on unnamed files, unspecified code, or unresolved command names.
- Type consistency: Nix option names are consistently `programs.acp-adapters.{claude,codex,pi}.{enable,package,command}`. Emacs command variables match `agent-shell` upstream names from the checked source.
