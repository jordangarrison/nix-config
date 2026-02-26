# programs.tea Home Manager Module Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a declarative Home Manager module for the `tea` CLI (Gitea/Forgejo) that generates `~/.config/tea/config.yml`.

**Architecture:** Custom Home Manager module at `modules/home/tea/default.nix` with `programs.tea` options namespace. Generates YAML config via `xdg.configFile` using `pkgs.writeText` and Nix's `builtins.toJSON` + a YAML generator. Follows the repo's existing custom module pattern (see `modules/home/languages/ruby.nix`, `modules/nixos/virtualization.nix`).

**Tech Stack:** Nix, Home Manager, `lib.generators.toYAML` or `builtins.toJSON` for config generation.

---

### Task 1: Create the module file with options

**Files:**
- Create: `modules/home/tea/default.nix`

**Step 1: Write the module with options and config generation**

```nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.tea;

  loginType = types.submodule {
    options = {
      url = mkOption {
        type = types.str;
        description = "Forgejo/Gitea instance URL";
        example = "http://endeavour.owl-yo.ts.net:7770";
      };

      user = mkOption {
        type = types.str;
        description = "Username on the instance";
      };

      default = mkOption {
        type = types.bool;
        default = false;
        description = "Whether this is the default login";
      };

      token = mkOption {
        type = types.str;
        default = "";
        description = "API access token (optional if using SSH)";
      };

      sshHost = mkOption {
        type = types.str;
        default = "";
        description = "SSH hostname for git operations";
      };

      sshKey = mkOption {
        type = types.str;
        default = "";
        description = "Path to SSH private key";
      };

      sshAgent = mkOption {
        type = types.bool;
        default = false;
        description = "Use SSH agent for authentication";
      };

      insecure = mkOption {
        type = types.bool;
        default = false;
        description = "Skip TLS verification";
      };
    };
  };

  # Convert login attrset to tea config.yml format
  loginToYaml = name: login: {
    inherit name;
    inherit (login) url user default insecure;
    token = if login.token != "" then login.token else "";
    ssh_host = if login.sshHost != "" then login.sshHost else "";
    ssh_key = if login.sshKey != "" then login.sshKey else "";
    ssh_agent = login.sshAgent;
  };

  teaConfig = {
    logins = mapAttrsToList loginToYaml cfg.logins;
    preferences = cfg.settings;
  };

  configFile = pkgs.runCommand "tea-config.yml" {
    nativeBuildInputs = [ pkgs.yq-go ];
    json = builtins.toJSON teaConfig;
    passAsFile = [ "json" ];
  } ''
    yq -P eval '.' "$jsonPath" > $out
  '';
in
{
  options.programs.tea = {
    enable = mkEnableOption "tea CLI for Gitea/Forgejo";

    package = mkOption {
      type = types.package;
      default = pkgs.tea;
      defaultText = literalExpression "pkgs.tea";
      description = "The tea package to install";
    };

    logins = mkOption {
      type = types.attrsOf loginType;
      default = { };
      description = "Forgejo/Gitea instance login configurations";
    };

    settings = mkOption {
      type = types.attrs;
      default = {
        editor = false;
        flag_defaults = {
          remote = "";
        };
      };
      description = "Tea preferences (editor, flag_defaults)";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile."tea/config.yml" = mkIf (cfg.logins != { }) {
      source = configFile;
    };
  };
}
```

**Step 2: Verify syntax**

Run: `nix flake check --no-build`
Expected: No errors from the new module (it won't be imported yet)

**Step 3: Commit**

```bash
git add modules/home/tea/default.nix
git commit -m "feat(tea): add programs.tea Home Manager module"
```

---

### Task 2: Wire the module into the user config

**Files:**
- Modify: `flake.nix` (endeavour's home-manager.users.jordangarrison.imports)

**Step 1: Add the tea module import to endeavour's jordangarrison Home Manager imports**

In `flake.nix`, find the endeavour inline config block and update the imports:

```nix
home-manager.users.jordangarrison.imports = [
  ./modules/home/niri
  ./modules/home/tea
];
```

**Step 2: Add tea configuration for jordangarrison**

In `users/jordangarrison/home.nix` or in the flake.nix inline config, add:

```nix
programs.tea = {
  enable = true;
  logins.endeavour = {
    url = "http://endeavour.owl-yo.ts.net:7770";
    user = "jordangarrison";
    default = true;
    sshHost = "endeavour.owl-yo.ts.net";
    sshKey = "~/.ssh/id_ed25519";
    sshAgent = true;
  };
};
```

**Step 3: Verify flake check passes**

Run: `git add -A && nix flake check --no-build`
Expected: All configurations pass

**Step 4: Commit**

```bash
git commit -m "feat(tea): configure tea CLI for jordangarrison on endeavour"
```

---

### Task 3: Test the deployment

**Step 1: Build**

Run: `nh os build .`
Expected: Build succeeds

**Step 2: Verify generated config**

Check the generated `config.yml` content in the nix store to make sure it looks correct before switching.

**Step 3: Switch**

Run: `nh os switch .`
Expected: Switch succeeds

**Step 4: Verify tea works**

Run: `tea login list`
Expected: Shows the endeavour login entry

Run: `tea repos`
Expected: Lists repos from the Forgejo instance
