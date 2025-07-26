{
  description =
    "Jordan Garrison's NixOS and Home Manager configurations for NixOS and MacOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
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
  };

  outputs = inputs@{ self, nixpkgs, nixos-hardware, nix-darwin, home-manager
    , aws-tools, aws-use-sso }: {
      nixosConfigurations = {
        "endeavour" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/nixos/common.nix
            ./modules/nixos/gnome-desktop.nix
            ./modules/nixos/hyprland-desktop.nix
            ./modules/nixos/fonts.nix
            ./modules/nixos/audio/pipewire.nix
            ./modules/nixos/development.nix
            ./modules/nixos/steam.nix
            ./modules/nixos/searx.nix
            ./modules/nixos/n8n.nix
            ./users/jordangarrison/nixos.nix
            ./users/mikayla/nixos.nix
            ./users/jane/nixos.nix
            ./users/isla/nixos.nix
            ./hosts/endeavour/configuration.nix
            nixos-hardware.nixosModules.msi-b550-a-pro
            nixos-hardware.nixosModules.common-gpu-amd
            home-manager.nixosModules.home-manager
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

              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }
          ];

        };
        "voyager" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/nixos/common.nix
            ./modules/nixos/gnome-desktop.nix
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

              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }
          ];

        };
        "discovery" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/nixos/common.nix
            ./modules/nixos/gnome-desktop.nix
            ./modules/nixos/audio/pipewire.nix
            ./users/jordangarrison/nixos.nix
            ./users/mikayla/nixos.nix
            ./users/jane/nixos.nix
            ./users/isla/nixos.nix
            ./hosts/discovery/configuration.nix
            nixos-hardware.nixosModules.common-cpu-amd
            nixos-hardware.nixosModules.common-pc-ssd
            home-manager.nixosModules.home-manager
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

              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }
          ];
        };
      };

      darwinConfigurations = {
        "H952L3DPHH" = nix-darwin.lib.darwinSystem {
          modules = [
            ./hosts/flomac/configuration.nix
            home-manager.darwinModules.home-manager
            {
              nix.enable = false;
              nixpkgs.config.allowUnfree = true;
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users."jordan.garrison" =
                  import ./users/jordangarrison/home-darwin.nix;
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
          modules = [ ./users/jordangarrison/home.nix ];
          extraSpecialArgs = {
            inherit inputs;
            username = "jordangarrison";
            homeDirectory = "/home/jordangarrison";
          };
        };
      };
    };
}
