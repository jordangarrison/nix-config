{ pkgs, lib, inputs, ... }:
let
  # This Mac serves local models to the rest of the tailnet (see the ollama
  # block near the bottom of this file). The port is ollama's default on both
  # sides of `tailscale serve`, so it appears in pi's provider baseUrl in
  # users/jordangarrison/home.nix as well — keep the two in sync.
  ollamaPort = 11434;
  ollamaBin = "/opt/homebrew/opt/ollama/bin/ollama";
  # The App Store build of Tailscale ships its CLI inside the bundle and puts
  # nothing on PATH.
  tailscaleBin = "/Applications/Tailscale.app/Contents/MacOS/Tailscale";
in
{

  environment.systemPackages = [ pkgs.vim pkgs.git ];
  programs.zsh.enable = true;
  system.primaryUser = "jordan.garrison";

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      # cleanup disabled — Homebrew 5.1.15 broke `brew bundle install --cleanup`
      # (requires --force/HOMEBREW_ASK). nix-darwin fix tracked in PR #1774 / issue #1787.
      cleanup = "none";
    };
    taps = [ "homebrew/services" "deskflow/homebrew-tap" "manaflow-ai/cmux" ];
    brews = [
      "fzf"
      "mas"
      # Installed by Homebrew, started by launchd.user.agents.ollama below —
      # `brew services` renders its plist straight from the formula and offers
      # no hook for the extra environment this host needs.
      "ollama"
      "wimlib"
    ];
    casks = [
      "1password"
      "1password-cli"
      "aws-vpn-client"
      "basecamp"
      "brave-browser"
      "chatgpt"
      "cmux"
      "chatgpt-atlas"
      "claude"
      "codex-app"
      "cursor"
      "deskflow"
      "orbstack"
      # "emacs-app"
      "espanso"
      "dbeaver-community"
      "discord"
      "ears"
      "figma"
      "firefox"
      "font-fira-code"
      "freelens"
      "ghostty"
      "google-drive"
      "jordanbaird-ice"
      "kdenlive"
      "linear"
      "linearmouse"
      "logseq"
      "obs"
      "obsidian"
      "openlens"
      "raspberry-pi-imager"
      "raycast"
      "readdle-spark"
      "rectangle"
      "signal"
      "slack"
      "superwhisper"
      "todoist-app"
      "visual-studio-code"
      "warp"
      "warp@preview"
      "wezterm"
      "windows-app"
      "zoom"
    ];
    # TODO: Re-enable masApps when mas 3.0.0 is released
    # Currently disabled due to mas-cli bug #1029: PKInstallErrorDomain 201 errors
    # on macOS 26.1+ preventing install/upgrade commands from working.
    # See: https://github.com/mas-cli/mas/issues (Issue #1029)
    # masApps = {
    #   "1Blocker" = 1365531024;
    #   "1Password for Safari" = 1569813296;
    #   "Actions" = 1586435171;
    #   "Amphetamine" = 937984704;
    #   "Awesome Screenshot & Recorder" = 1531282066;
    #   "Copilot" = 1447330651;
    #   "Dark Reader for Safari" = 1438243180;
    #   "Data Jar" = 1453273600;
    #   "Exporter" = 1099120373;
    #   "Flow" = 1423210932;
    #   "GarageBand" = 682658836;
    #   "HotKey" = 975890633;
    #   "iMovie" = 408981434;
    #   "JSONPeep" = 1458969831;
    #   "Ka-Block!" = 1335413823;
    #   "Keymapp" = 6472865291;
    #   "Keynote" = 409183694;
    #   "Kindle" = 302584613;
    #   "Notability" = 360593530;
    #   "Numbers" = 409203825;
    #   "Okta Extension App" = 1439967473;
    #   "OmniFocus" = 1542143627;
    #   "Online Check" = 6504709660;
    #   "Ooooo" = 1482773008;
    #   "Pages" = 409201541;
    #   "Perplexity" = 6714467650;
    #   "S3" = 6447647340;
    #   "Save to Reader" = 1640236961;
    #   "Sequel Ace" = 1518036000;
    #   "Shareful" = 1522267256;
    #   "Shell Fish" = 1336634154;
    #   "Streaks" = 963034692;
    #   "Swift Playground" = 1496833156;
    #   "Tailscale" = 1475387142;
    #   "Taskheat" = 1431995750;
    #   "Velja" = 1607635845;
    #   "WhatsApp" = 310633997;
    #   "Xcode" = 497799835;
    # };
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  # Ollama, exposed to the tailnet so pi on the Linux boxes can drive the M4
  # Pro's GPU. Three things here are load-bearing and non-obvious.
  #
  # 1. nix-darwin owns the launchd agent instead of `brew services`. The
  #    formula's service block hardcodes its own plist (including
  #    OLLAMA_FLASH_ATTENTION and OLLAMA_KV_CACHE_TYPE) and Homebrew exposes
  #    no way to add environment variables to it, so setting OLLAMA_HOST at
  #    all means writing the plist ourselves.
  #
  # 2. OLLAMA_HOST binds 0.0.0.0, not loopback. Ollama enforces a Host-header
  #    allowlist — localhost, *.local, *.internal and bare IPs — as
  #    DNS-rebinding protection, but *only while it is listening on a loopback
  #    address*. `tailscale serve` forwards the client's Host verbatim, and
  #    the MagicDNS name is a .ts.net, so a loopback-bound ollama answers
  #    every tailnet request with an empty 403. Binding a non-loopback address
  #    switches the check off. Binding the tailnet IP directly would be the
  #    tidier fix, but then the address only exists while Tailscale is up and
  #    local clients on 127.0.0.1 (Superwhisper, cmux, `ollama run`) break.
  #
  # 3. 0.0.0.0 is not the same as "on the LAN" here. The only way in is
  #    `tailscale serve`, which terminates inside tailscaled and dials ollama
  #    over loopback; inbound connections straight to port 11434 are dropped
  #    by the macOS application firewall, which is asserted below precisely
  #    because it is what keeps this bind private. Approving ollama in the
  #    firewall prompt would publish the model server to whatever coffee-shop
  #    Wi-Fi this laptop is on — don't.
  networking.applicationFirewall = {
    enable = true;
    allowSigned = true;
    allowSignedApp = true;
  };

  launchd.user.agents.ollama = {
    command = "${ollamaBin} serve";
    environment = {
      OLLAMA_HOST = "0.0.0.0:${toString ollamaPort}";
      # Ollama defaults to a 4096-token context. A pi agent turn measured
      # 18k-43k prompt tokens on this setup (system prompt, tool definitions
      # and skills, re-sent every turn), so the default truncates the agent's
      # own instructions before any real work fits. 64k covers the preamble
      # with room for a few file reads. pi's contextWindow for these models
      # must not exceed this value or ollama truncates silently.
      OLLAMA_CONTEXT_LENGTH = "65536";
      # Loading a ~22 GiB model and prefilling that preamble cold costs
      # minutes; once warm, ollama reuses the cached prefix and turns land
      # around a minute. The 5m default throws the warm state away over a
      # coffee break, so hold it longer — at the price of ~24 GiB of this
      # laptop's 48 GiB staying resident for half an hour after the last
      # request. Lower it if the Mac starts feeling tight.
      OLLAMA_KEEP_ALIVE = "30m";
    };
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
      WorkingDirectory = "/opt/homebrew/var";
      StandardOutPath = "/opt/homebrew/var/log/ollama.log";
      StandardErrorPath = "/opt/homebrew/var/log/ollama.log";
    };
  };

  # `tailscale serve` state already survives reboots, so this agent exists to
  # keep the mapping declarative and to re-apply it on a fresh machine. It is
  # a one-shot: serve --bg returns as soon as the proxy is registered.
  # tailscaled and this agent both start at login, so retry rather than assume
  # an ordering.
  launchd.user.agents.ollama-tailnet-serve = {
    script = ''
      for _ in $(seq 1 60); do
        if ${tailscaleBin} serve --bg \
          --https=${toString ollamaPort} http://127.0.0.1:${toString ollamaPort}; then
          exit 0
        fi
        sleep 10
      done
      echo "tailscaled never accepted the serve config; giving up" >&2
      exit 1
    '';
    serviceConfig = {
      RunAtLoad = true;
      StandardOutPath = "/opt/homebrew/var/log/ollama-tailnet-serve.log";
      StandardErrorPath = "/opt/homebrew/var/log/ollama-tailnet-serve.log";
    };
  };

  system = {
    defaults = {
      dock = {
        autohide = true;
        orientation = "bottom";
        show-process-indicators = false;
      };
      finder = {
        AppleShowAllExtensions = true;
        ShowPathbar = true;
      };
      NSGlobalDomain = {
        ApplePressAndHoldEnabled = false;
        InitialKeyRepeat = 10;
        KeyRepeat = 1;
      };
      trackpad = { Clicking = true; };
      WindowManager = { GloballyEnabled = true; };
    };
    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToEscape = true;
    };
  };
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 6;
}
