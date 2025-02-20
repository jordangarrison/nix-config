{ pkgs, lib, inputs, ... }: {
  environment.systemPackages = [
    pkgs.vim
    pkgs.git
  ];
  programs.zsh.enable = true;
  homebrew = {
    enable = true;
    brews = [
      "sharewifi"
    ];
    casks = [
      "1password"
      "1password-cli"
      "brave-browser"
      "cursor"
      "dbeaver-community"
      "ears"
      "figma"
      "firefox"
      "font-fira-code"
      "ghostty"
      "jordanbaird-ice"
      "linearmouse"
      "raycast"
      "rectangle"
      "visual-studio-code"
      "wezterm"
    ];
    masApps = {
      "1Blocker" = 1365531024;
      "1Password for Safari" = 1569813296;
      "Actions" = 1586435171;
      "Amphetamine" = 937984704;
      "Awesome Screenshot & Recorder" = 1531282066;
      "Copilot" = 1447330651;
      "Dark Reader for Safari" = 1438243180;
      "Data Jar" = 1453273600;
      "Exporter" = 1099120373;
      "Flow" = 1423210932;
      "GarageBand" = 682658836;
      "HotKey" = 975890633;
      "iMovie" = 408981434;
      "JSONPeep" = 1458969831;
      "Ka-Block!" = 1335413823;
      "Keymapp" = 6472865291;
      "Keynote" = 409183694;
      "Kindle" = 302584613;
      "Notability" = 360593530;
      "Numbers" = 409203825;
      "Okta Extension App" = 1439967473;
      "OmniFocus" = 1542143627;
      "Online Check" = 6504709660;
      "Ooooo" = 1482773008;
      "Pages" = 409201541;
      "Perplexity" = 6714467650;
      "S3" = 6447647340;
      "Save to Reader" = 1640236961;
      "Sequel Ace" = 1518036000;
      "Shareful" = 1522267256;
      "Shell Fish" = 1336634154;
      "Streaks" = 963034692;
      "Swift Playground" = 1496833156;
      "Tailscale" = 1475387142;
      "Taskheat" = 1431995750;
      "Velja" = 1607635845;
      "WhatsApp" = 310633997;
      "Xcode" = 497799835;
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
    };
    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToEscape = true;
    };
  };
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 6;
}
