{ inputs, pkgs, ... }:

{
  services.tic-tac-toe-4-in-a-row = {
    enable = true;
    package = inputs.tic-tac-toe-4-in-a-row.packages.${pkgs.stdenv.hostPlatform.system}.default;
    host = "four.jordangarrison.dev";
    listenAddress = "127.0.0.1";
    port = 4002;
    openFirewall = false;
    nginx.enable = false;
  };
}
