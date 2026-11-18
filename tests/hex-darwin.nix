# nix eval --json --impure --expr 'import ./tests/hex-darwin.nix { flake = builtins.getFlake (toString ./.); }'
{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  darwin = flake.darwinConfigurations.H952L3DPHH;
  home = darwin.config.home-manager.users."jordan.garrison";
  hex = lib.findFirst (p: (p.pname or "") == "hex-dictation") null home.home.packages;
in
assert lib.assertMsg (hex != null) "Mac home does not install Hex dictation";
let
  results = {
    pinnedRelease =
      hex.version == "3.4.0"
      &&
        hex.src.url
        == "https://github.com/anomalyco/hex/releases/download/v${hex.version}/hex-${hex.version}-macos-arm64.zip"
      &&
        hex.src.outputHash == builtins.convertHash {
          hash = "1ab0242dc3bb011c88568903cbf1e9d30310867a46f5168309853d6f8b4ca650";
          hashAlgo = "sha256";
          toHashFormat = "sri";
        };
    signaturePreserved = hex.dontFixup;
    macOnly = hex.meta.platforms == [ "aarch64-darwin" ];
    copiedApp =
      home.targets.darwin.copyApps.enable
      && !home.targets.darwin.linkApps.enable
      && home.targets.darwin.copyApps.directory == "Applications/Home Manager Apps";
    unknownVersionRejected =
      !(builtins.tryEval (hex.override { version = "missing-release"; }).src.outputHash).success;
  };
in
assert lib.assertMsg (lib.all (x: x) (builtins.attrValues results)) "Hex Darwin checks failed";
results
