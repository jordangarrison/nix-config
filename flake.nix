{
  description = "Jordan Garrison's NixOS and Home Manager configurations for NixOS and MacOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, nix-darwin, home-manager }: {
    darwinConfigurations = {
      "JJHJLQ747Q" = nix-darwin.lib.darwinSystem {
        modules = [
          flomac/configuration.nix
          home-manager.darwinModules.home-manager
          {
            ids.gids.nixbld = 30000;
            nixpkgs.config.allowUnfree = true;
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users."jordan.garrison" = import ./users/jordangarrison/home.nix;
            };
            users.users."jordan.garrison" = {
              home = "/Users/jordan.garrison";
            };
          }
        ];
        specialArgs = { inherit inputs; };
      };
      "H952L3DPHH" = nix-darwin.lib.darwinSystem {
        modules = [
          flomac/configuration.nix
          home-manager.darwinModules.home-manager
          {
            nixpkgs.config.allowUnfree = true;
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users."jordan.garrison" = import ./users/jordangarrison/home.nix;
            };
            users.users."jordan.garrison" = {
              home = "/Users/jordan.garrison";
            };
          }
        ];
      };
    };
  };
}
