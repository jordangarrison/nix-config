{ config
, lib
, pkgs
, ...
}:

let
  cfg = config.programs.orca;
  package = cfg.package.override {
    inherit (cfg) waylandSupport x11Support headlessSupport;
  };
in
{
  options.programs.orca = {
    enable = lib.mkEnableOption "Orca agent-fleet ADE";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.orca-ide;
      defaultText = lib.literalExpression "pkgs.orca-ide";
      description = "The Orca package to install.";
    };

    waylandSupport = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to include Wayland clipboard runtime tooling.";
    };

    x11Support = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to include X11 automation and clipboard runtime tooling.";
    };

    headlessSupport = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to include Xvfb for headless browser panes.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ package ];

    # Orca's mutable CLI installer writes this path directly. Own it so the
    # packaged dispatcher and its runtime environment always take precedence.
    home.file.".local/bin/orca-ide" = {
      source = "${package}/bin/orca-ide";
      force = true;
    };
  };
}
