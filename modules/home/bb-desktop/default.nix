{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.bb-desktop;
  serverTargetPath = "${config.xdg.configHome}/bb/server-target.json";
  serverTargetSeed = pkgs.writeText "bb-desktop-server-target.json" (
    builtins.toJSON {
      customServerUrl = cfg.defaultServerUrl;
      customServerUrls = [ cfg.defaultServerUrl ];
      target = "custom";
    }
  );
in
{
  options.programs.bb-desktop = {
    enable = lib.mkEnableOption "BB desktop";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../packages/bb-desktop { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../packages/bb-desktop { }";
      description = "The BB desktop package to install.";
    };

    defaultServerUrl = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "https?://[^[:space:]]+");
      default = null;
      example = "https://bb.jordangarrison.dev";
      description = ''
        Server to select when the app has no saved server setting. Existing
        choices are preserved, and the app can change the setting later.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # This is mutable app state. Do not make it a Home Manager symlink.
    home.activation.bbDesktopServerTarget = lib.mkIf (cfg.defaultServerUrl != null) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -e ${lib.escapeShellArg serverTargetPath} ] \
          && [ ! -L ${lib.escapeShellArg serverTargetPath} ]; then
          run ${lib.getExe' pkgs.coreutils "install"} -Dm600 \
            ${serverTargetSeed} ${lib.escapeShellArg serverTargetPath}
        fi
      ''
    );
  };
}
