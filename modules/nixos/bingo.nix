{ inputs, pkgs, ... }:

{
  services.bingo = {
    enable = true;
    package = inputs.bingo.packages.${pkgs.stdenv.hostPlatform.system}.default;
    host = "bingo.garrisonsbygrace.com";
    listenAddress = "127.0.0.1";
    port = 4003;
    openFirewall = false;
    nginx.enable = false;
    callerPinFile = "/var/lib/bingo/secrets/caller-pin";
    inviteCodeFile = "/var/lib/bingo/secrets/invite-code";
    sessionSecretFile = "/var/lib/bingo/secrets/session-secret";
  };
}
