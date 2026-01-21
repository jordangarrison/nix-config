{
  description = "Jordan Garrison's NixOS and Home Manager configurations for NixOS and MacOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-master.url = "github:nixos/nixpkgs/master";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nvf = {
      url = "github:NotAShelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    aws-tools = {
      url = "github:jordangarrison/aws-tools";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    aws-use-sso = {
      url = "github:jordangarrison/aws-use-sso";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hubctl = {
      url = "github:jordangarrison/hubctl";
      # inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-code.url = "github:sadjow/claude-code-nix";
    niri.url = "github:sodiboo/niri-flake";
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sweet-nothings = {
      url = "github:jordangarrison/sweet-nothings";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-zed-extensions = {
      url = "github:DuskSystems/nix-zed-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-stable,
      nixpkgs-master,
      nixos-hardware,
      nix-darwin,
      home-manager,
      nvf,
      aws-tools,
      aws-use-sso,
      hubctl,
      claude-code,
      niri,
      noctalia,
      sweet-nothings,
      nix-zed-extensions,
    }:
    {
      nixosConfigurations = {
        "endeavour" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/stable-overlay.nix
            ./modules/master-overlay.nix
            ./modules/zed-extensions-overlay.nix
            ./modules/ralph-overlay.nix
            ./modules/scripts-overlay.nix
            ./modules/nixos/common.nix
            ./modules/nixos/brother-printer.nix
            ./modules/nixos/lan.nix
            ./modules/nixos/gnome-desktop.nix
            # ./modules/nixos/hyprland-desktop.nix  # Disabled in favor of Niri
            ./modules/nixos/niri-desktop.nix
            ./modules/nixos/fonts.nix
            ./modules/nixos/audio/pipewire.nix
            ./modules/nixos/development.nix
            ./modules/nixos/steam.nix
            ./modules/nixos/searx.nix
            ./modules/nixos/metabase.nix
            ./modules/nixos/postgres.nix
            ./modules/nixos/n8n.nix
            ./modules/nixos/jellyfin.nix
            ./modules/nixos/virtualization.nix
            ./modules/nixos/freerdp.nix
            ./users/jordangarrison/nixos.nix
            ./users/mikayla/nixos.nix
            ./users/jane/nixos.nix
            ./users/isla/nixos.nix
            ./hosts/endeavour/configuration.nix
            nixos-hardware.nixosModules.msi-b550-a-pro
            nixos-hardware.nixosModules.common-gpu-amd
            home-manager.nixosModules.home-manager
            ./modules/home/defaults.nix
            {
              # Configure users for endeavour
              users.jordangarrison = {
                enable = true;
                username = "jordangarrison";
                homeDirectory = "/home/jordangarrison";
              };

              users.mikayla = {
                enable = true;
                homeDirectory = "/home/mikayla";
              };

              users.jane = {
                enable = true;
                homeDirectory = "/home/jane";
              };

              users.isla = {
                enable = true;
                homeDirectory = "/home/isla";
              };

              # Enable virtualization with virt-manager
              virtualization.virt-manager = {
                enable = true;
                users = [ "jordangarrison" ];
              };

              # Enable FreeRDP
              services.freerdp.enable = true;

              # Import niri home module for jordangarrison on endeavour
              home-manager.users.jordangarrison.imports = [ ./modules/home/niri ];
            }
          ];

        };
        "opportunity" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/stable-overlay.nix
            ./modules/master-overlay.nix
            ./modules/zed-extensions-overlay.nix
            ./modules/ralph-overlay.nix
            ./modules/scripts-overlay.nix
            ./modules/nixos/common.nix
            ./modules/nixos/brother-printer.nix
            ./modules/nixos/lan.nix
            ./modules/nixos/gnome-desktop.nix
            # ./modules/nixos/hyprland-desktop.nix  # Disabled in favor of Niri
            ./modules/nixos/niri-desktop.nix
            { gbg-config.machine.type = "laptop"; }
            ./modules/nixos/fonts.nix
            ./modules/nixos/audio/pipewire.nix
            ./modules/nixos/development.nix
            ./modules/nixos/virtualization.nix
            ./modules/nixos/tablet-mode.nix
            ./users/jordangarrison/nixos.nix
            ./users/mikayla/nixos.nix
            ./users/jane/nixos.nix
            ./users/isla/nixos.nix
            ./hosts/opportunity/configuration.nix
            nixos-hardware.nixosModules.framework-12-13th-gen-intel
            home-manager.nixosModules.home-manager
            ./modules/home/defaults.nix
            {
              # Configure users for voyager
              users.jordangarrison = {
                enable = true;
                username = "jordangarrison";
                homeDirectory = "/home/jordangarrison";
                swapSuperAlt = true;
              };

              users.mikayla = {
                enable = true;
                homeDirectory = "/home/mikayla";
              };

              users.jane = {
                enable = true;
                homeDirectory = "/home/jane";
              };

              users.isla = {
                enable = true;
                homeDirectory = "/home/isla";
              };

              # Import niri and tablet-mode home modules for jordangarrison on opportunity
              home-manager.users.jordangarrison.imports = [
                ./modules/home/niri
                ./modules/home/tablet-mode
              ];

              # Enable virtualization with virt-manager
              virtualization.virt-manager = {
                enable = true;
                users = [ "jordangarrison" ];
              };

              # Enable tablet mode for Framework 12 touchscreen
              tablet-mode.enable = true;
            }
          ];

        };
        "voyager" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/stable-overlay.nix
            ./modules/master-overlay.nix
            ./modules/ralph-overlay.nix
            ./modules/scripts-overlay.nix
            ./modules/nixos/common.nix
            ./modules/nixos/brother-printer.nix
            ./modules/nixos/lan.nix
            ./modules/nixos/gnome-desktop.nix
            { gbg-config.machine.type = "laptop"; }
            # ./modules/nixos/hyprland-desktop.nix  # Disabled - voyager uses GNOME only
            ./modules/nixos/fonts.nix
            ./modules/nixos/audio/pipewire.nix
            ./modules/nixos/development.nix
            ./users/jordangarrison/nixos.nix
            ./users/mikayla/nixos.nix
            ./users/jane/nixos.nix
            ./users/isla/nixos.nix
            ./hosts/voyager/configuration.nix
            nixos-hardware.nixosModules.apple-macbook-pro-12-1
            home-manager.nixosModules.home-manager
            ./modules/home/defaults.nix
            {
              # Configure users for voyager
              users.jordangarrison = {
                enable = true;
                username = "jordan";
                homeDirectory = "/home/jordan";
              };

              users.mikayla = {
                enable = true;
                homeDirectory = "/home/mikayla";
              };

              users.jane = {
                enable = true;
                homeDirectory = "/home/jane";
              };

              users.isla = {
                enable = true;
                homeDirectory = "/home/isla";
              };
            }
          ];

        };
        "discovery" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/stable-overlay.nix
            ./modules/master-overlay.nix
            ./modules/ralph-overlay.nix
            ./modules/scripts-overlay.nix
            ./modules/nixos/common.nix
            ./modules/nixos/brother-printer.nix
            ./modules/nixos/lan.nix
            ./modules/nixos/gnome-desktop.nix
            ./modules/nixos/fonts.nix
            ./modules/nixos/audio/pipewire.nix
            ./users/jordangarrison/nixos.nix
            ./users/mikayla/nixos.nix
            ./users/jane/nixos.nix
            ./users/isla/nixos.nix
            ./hosts/discovery/configuration.nix
            nixos-hardware.nixosModules.common-cpu-amd
            nixos-hardware.nixosModules.common-pc-ssd
            home-manager.nixosModules.home-manager
            ./modules/home/defaults.nix
            {
              # Configure users for discovery
              users.jordangarrison = {
                enable = true;
                username = "jordangarrison";
                homeDirectory = "/home/jordangarrison";
              };

              users.mikayla = {
                enable = true;
                homeDirectory = "/home/mikayla";
              };

              users.jane = {
                enable = true;
                homeDirectory = "/home/jane";
              };

              users.isla = {
                enable = true;
                homeDirectory = "/home/isla";
              };
            }
          ];
        };
      };

      darwinConfigurations = {
        "H952L3DPHH" = nix-darwin.lib.darwinSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/stable-overlay.nix
            ./modules/master-overlay.nix
            ./modules/ralph-overlay.nix
            ./modules/scripts-overlay.nix
            ./modules/nixos/emacs.nix
            ./modules/nixos/fonts.nix
            ./hosts/flomac/configuration.nix
            home-manager.darwinModules.home-manager
            ./modules/home/defaults.nix
            {
              nix.enable = false;
              nixpkgs.config.allowUnfree = true;
              home-manager = {
                users."jordan.garrison" = import ./users/jordangarrison/home-darwin.nix;
                extraSpecialArgs = {
                  inherit inputs;
                  username = "jordan.garrison";
                  homeDirectory = "/Users/jordan.garrison";
                };
              };
              users.users."jordan.garrison" = {
                home = "/Users/jordan.garrison";
              };
            }
          ];
        };
      };

      # Ubuntu/WSL configuration
      homeConfigurations = {
        "jordangarrison@normandy" = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
          modules = [
            ./modules/stable-overlay.nix
            ./modules/master-overlay.nix
            ./modules/ralph-overlay.nix
            ./modules/scripts-overlay.nix
            ./users/jordangarrison/home.nix
          ];
          extraSpecialArgs = {
            inherit inputs;
            username = "jordangarrison";
            homeDirectory = "/home/jordangarrison";
          };
        };
      };
    };
}
