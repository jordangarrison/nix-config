{ config, lib, pkgs, ... }:

# Super Productivity desktop (Electron) app. Shared by NixOS and nix-darwin,
# so it must not touch NixOS-only options; the server lives in server.nix.
#
# Sync settings live in the app's own IndexedDB, so Nix can't write them. On
# Linux the app is launched with --custom-url pointing at our server instead:
# it then runs the hosted build, whose sync form comes pre-filled with the
# WebDAV URL and username, leaving only the password to type once per device.
# The macOS .app bundle can't take launch flags, and a terminal-only flag
# would split data between two origins, so macOS runs the bundled build and
# the URL and username are typed by hand.
let
  cfg = config.programs.super-productivity;

  withServer = pkgs.symlinkJoin {
    name = "super-productivity-${cfg.package.version}";
    paths = [ cfg.package ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm $out/bin/superproductivity $out/bin/super-productivity
      makeWrapper ${lib.getExe cfg.package} $out/bin/superproductivity \
        --add-flags ${lib.escapeShellArg "--custom-url=${cfg.serverUrl}"}
      ln -s superproductivity $out/bin/super-productivity
    '';
    inherit (cfg.package) meta;
  };
in
{
  options.programs.super-productivity = {
    enable = lib.mkEnableOption "the Super Productivity desktop app";

    package = lib.mkPackageOption pkgs "super-productivity" { };

    serverUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      # Keep in step with services.super-productivity.domain's default.
      default = "https://superproductivity.jordangarrison.dev";
      description = ''
        Self-hosted web app the Linux desktop app loads instead of its bundled
        build, so sync comes pre-configured. null runs the bundled build.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (if pkgs.stdenv.hostPlatform.isLinux && cfg.serverUrl != null
       then withServer
       else cfg.package)
    ];
  };
}
