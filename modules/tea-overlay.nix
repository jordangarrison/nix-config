{ config, lib, pkgs, ... }:

{
  # TODO: Remove this overlay when nixpkgs updates tea to >= 0.12.0
  # 0.12.0 fixes the default login fallback prompt (gitea/tea#839)
  nixpkgs.overlays = [
    (final: prev: {
      tea = prev.tea.overrideAttrs (old: rec {
        version = "0.12.0";
        src = prev.fetchFromGitea {
          domain = "gitea.com";
          owner = "gitea";
          repo = "tea";
          rev = "v${version}";
          sha256 = "sha256-yaktVULY9eGRyWVqbwjZSo5d9DhHJMycfdEwZgxaLnw=";
        };
        vendorHash = "sha256-u4GTrdxmsfxC8s0LwQbsbky/zk1pW5VNSp4+7ZCIxzY=";
        ldflags = [
          "-X code.gitea.io/tea/cmd.Version=${version}"
        ];
        # Config test fails in nix sandbox (can't create config file)
        doCheck = false;
      });
    })
  ];
}
