{
  # CI stub for the private jordangarrison/jagpi flake, which is fetched
  # over SSH and unreachable from credential-less GitHub-hosted runners.
  # It mirrors only the interface this repo consumes (see
  # hosts/endeavour/jagpi.nix): packages.<system>.{default,jagpi}, the
  # claude-bridge provider package with its passthru.jagpiProvider path, and
  # homeManagerModules.default with the services.jagpi options the host
  # sets, typed like upstream, that installs the package and writes the
  # providers part of config.json. integrations/herdr-app/ holds the board
  # mod and layout that modules/home/herdr-app reads (the layout at
  # evaluation time). If that surface grows, grow this stub to match.
  description = "CI stub for the private jordangarrison/jagpi flake";

  outputs =
    { self }:
    let
      stubFor = system: rec {
        jagpi = derivation {
          name = "jagpi-stub";
          inherit system;
          builder = "/bin/sh";
          args = [
            "-c"
            "echo ci-stub > $out"
          ];
        };
        default = jagpi;
        claude-bridge =
          derivation {
            name = "jagpi-claude-bridge-stub";
            inherit system;
            builder = "/bin/sh";
            args = [
              "-c"
              "echo ci-stub > $out"
            ];
          }
          // {
            jagpiProvider = "lib/claude-bridge/src/hosts/jagpi.ts";
          };
      };
    in
    {
      packages.x86_64-linux = stubFor "x86_64-linux";
      packages.aarch64-darwin = stubFor "aarch64-darwin";

      homeManagerModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.services.jagpi;
        in
        {
          # Typed like upstream, so a misspelled option or a bad value fails
          # CI. environmentFile is here so the Slack follow-up stays one line.
          options.services.jagpi = {
            enable = lib.mkEnableOption "the jagpi daemon (CI stub)";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              defaultText = lib.literalExpression "jagpi.packages.\${system}.default";
              description = "The jagpi package. It is also installed, so `jagpi` opens the TUI on this instance.";
            };
            # Contract-only: CI does not build or exercise the upstream launcher.
            acp.enable = lib.mkEnableOption "the jagpi ACP launcher (CI stub)";
            instance = lib.mkOption {
              type = lib.types.strMatching "[a-z][a-z0-9-]{0,31}";
              default = "default";
            };
            environmentFile = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
            };
            # Mirror upstream's free-form JSON contract; no runtime settings are changed (#156).
            settings = lib.mkOption {
              type = (pkgs.formats.json { }).type;
              default = { };
            };
            memory.caps.projects = lib.mkOption {
              type = lib.types.attrsOf (lib.types.ints.between 1 9007199254740991);
              default = { };
            };
            herdr.package = lib.mkPackageOption pkgs "herdr" { };
            providers = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    package = lib.mkOption { type = lib.types.package; };
                    module = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                    };
                    options = lib.mkOption {
                      type = (pkgs.formats.json { }).type;
                      default = { };
                    };
                    runtimePackages = lib.mkOption {
                      type = lib.types.listOf lib.types.package;
                      default = [ ];
                    };
                  };
                }
              );
              default = [ ];
            };
          };
          # Like upstream, a provider without `module` must name one in
          # passthru.jagpiProvider; reading it here fails CI when it does not.
          config = lib.mkIf cfg.enable {
            # runtimePackages are only type-checked: upstream puts them on
            # the daemon's PATH, not in the user profile.
            home.packages = [ cfg.package ];
            xdg.configFile."jagpi/${cfg.instance}/config.json".text = builtins.toJSON (
              {
                providers = map (plugin: {
                  module = "${plugin.package}/${
                    if plugin.module != null then plugin.module else plugin.package.jagpiProvider
                  }";
                  inherit (plugin) options;
                }) cfg.providers;
              }
              // lib.optionalAttrs (cfg.memory.caps.projects != { }) {
                memory.caps.projects = cfg.memory.caps.projects;
              }
            );
          };
        };
    };
}
