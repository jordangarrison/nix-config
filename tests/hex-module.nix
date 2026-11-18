# nix eval --json --impure --expr 'import ./tests/hex-module.nix { flake = builtins.getFlake (toString ./.); }'
{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  mkHome = enable: (flake.inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
    extraSpecialArgs = {
      inputs = flake.inputs;
      userApps.hex.enable = enable;
    };
    modules = [
      ../modules/home/hex
      {
        home.username = "developer";
        home.homeDirectory = "/home/developer";
        home.stateVersion = "25.05";
      }
    ];
  }).config;
  disabled = mkHome false;
  enabled = mkHome true;
  service = enabled.systemd.user.services.hex;
  host = name: flake.nixosConfigurations.${name}.config;
  home = name: (host name).home-manager.users.jordangarrison;
  reenabledHome = name: ((flake.nixosConfigurations.${name}.extendModules {
    modules = [{ users.jordangarrison.apps.hex.enable = lib.mkForce true; }];
  }).config.home-manager.users.jordangarrison);
  results = {
    disabledHasNoService = !(disabled.systemd.user.services ? hex);
    disabledInstallsNoHex = !(lib.elem enabled.programs.hex.package disabled.home.packages);
    enabledInstallsHex = lib.elem enabled.programs.hex.package enabled.home.packages;
    pinnedRelease = enabled.programs.hex.package.version == "3.4.0";
    graphicalSessionOnly = service.Install.WantedBy == [ "graphical-session.target" ]
      && service.Unit.PartOf == [ "graphical-session.target" ]
      && service.Unit.After == [ "graphical-session.target" ];
    supervised = service.Service.Type == "notify"
      && service.Service.Restart == "on-failure";
    privateData = service.Service.UMask == "0077"
      && service.Service.Environment == [ "HEX_APPLICATION_SUPPORT_DIR=/home/developer/.local/share/hex" ];
    distinctShortcut = enabled.programs.hex.shortcut == "control+option+space"
      && enabled.programs.hex.settings.shortcut_mode == "toggle";
    noAutomaticModelDownload = !(enabled.systemd.user.services ? hex-model)
      && enabled.programs.hex.model == "parakeet_v3";
    disabledOnDesktops = lib.all (name:
      !(host name).users.jordangarrison.apps.hex.enable
      && !(home name).programs.hex.enable
      && !((home name).systemd.user.services ? hex)
      && !((home name).systemd.user.services ? hex-model)
      && !(lib.elem (home name).programs.hex.package (home name).home.packages)
    ) [ "endeavour" "opportunity" "discovery" ];
    noNiriShortcut = lib.all (name:
      !((home name).programs.niri.settings.binds ? "Ctrl+Alt+Space")
    ) [ "endeavour" "opportunity" ];
    reenabledNiriShortcut = lib.all (name:
      let home = reenabledHome name; in
      home.programs.hex.enable
      && home.programs.hex.autostart
      && home.systemd.user.services ? hex
      && lib.elem home.programs.hex.package home.home.packages
      && home.programs.niri.settings.binds."Ctrl+Alt+Space".action.spawn == [
        (lib.getExe home.programs.hex.package) "dictation" "toggle"
      ]) [ "endeavour" "opportunity" ];
    handyUnchanged = lib.all (name: (host name).users.jordangarrison.apps.handy.enable
      && (home name).systemd.user.services ? handy) [ "endeavour" "opportunity" ];
    noWslModule = !(flake.homeConfigurations."jordangarrison@normandy".config.programs ? hex);
    darwinPackageKept = lib.any (pkg: (lib.getName pkg) == "hex-dictation")
      flake.darwinConfigurations.H952L3DPHH.config.home-manager.users."jordan.garrison".home.packages;
    noDarwinModule = !(flake.darwinConfigurations.H952L3DPHH.config.home-manager.users."jordan.garrison".programs ? hex);
  };
in
assert lib.assertMsg (lib.all (x: x) (builtins.attrValues results)) "Hex module checks failed";
results
