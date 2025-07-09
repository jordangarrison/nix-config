{
  description = "Jordan Garrison's NixOS and Home Manager configurations for NixOS and MacOS";

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

  outputs = inputs@{ self, nixpkgs, nixos-hardware, nix-darwin, home-manager, aws-tools, aws-use-sso }: {
    nixosConfigurations = {
      "endeavour" = nixpkgs.lib.nixosSystem {
        modules = [
          ./modules/nixos/common.nix
          ./modules/gnome-desktop.nix
          ./modules/nixos/audio/pipewire.nix
          ./modules/nixos/development.nix
          ./endeavour/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            users.users.jordangarrison = {
              isNormalUser = true;
              extraGroups = [ "wheel" ];
              home = "/home/jordangarrison";
            };
            home-manager.users = {
              jordangarrison = import ./users/jordangarrison/home.nix;
            };
            home-manager.extraSpecialArgs = {
              inherit inputs;
              username = "jordangarrison";
              homeDirectory = "/home/jordangarrison";
            };
          }
        ];

      };
      "voyager" = nixpkgs.lib.nixosSystem {
        modules = [
          ./modules/nixos/common.nix
          ./modules/gnome-desktop.nix
          ./modules/nixos/audio/pipewire.nix
          ./modules/nixos/development.nix
          ./voyager/configuration.nix
          nixos-hardware.nixosModules.apple-macbook-pro-12-1
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            users.users.jordan = {
              isNormalUser = true;
              extraGroups = [ "wheel" ];
              home = "/home/jordan";
            };
            home-manager.users = {
              jordan = import ./users/jordangarrison/home.nix;
            };
            home-manager.extraSpecialArgs = {
              inherit inputs;
              username = "jordan";
              homeDirectory = "/home/jordan";
            };
          }
        ];

      };
    };

    darwinConfigurations = {
      "H952L3DPHH" = nix-darwin.lib.darwinSystem {
        modules = [
          flomac/configuration.nix
          home-manager.darwinModules.home-manager
          {
            nix.enable = false;
            nixpkgs.config.allowUnfree = true;
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users."jordan.garrison" = import ./users/jordangarrison/home.nix;
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
