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
  };

  outputs = inputs@{ self, nixpkgs, nixos-hardware, nix-darwin, home-manager }: {
    nixosConfigurations = {
      "voyager" = nixpkgs.lib.nixosSystem {
        modules = [
	  voyager/configuration.nix
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
        extraSpecialArgs = { inherit inputs; };
      };
    };
  };
}
