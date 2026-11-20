# nix eval --json --impure --expr 'import ./tests/remote-access-policy.nix { flake = builtins.getFlake (toString ./.); }'
#
# The firewall and keys-only SSH must never cut off Tailscale or SSH. These
# are the promises, per host. tests/firewall-runtime.nix proves the same
# rules on a running system.
{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;

  # Key comments in users/jordangarrison/nixos.nix for every device that logs
  # in today. "discovery-gh-cli" is endeavour's own key: deploy-rs (to
  # localhost and discovery) and endeavour -> discovery use it.
  loginKeys = [
    "flosports" # work Mac
    "herdr-mobile" # phone
    "discovery-gh-cli" # endeavour
    "opportunity"
  ];
  # A laptop keeps SSH on the tailnet only; the desktops also allow the LAN.
  sshOnLan = { endeavour = true; discovery = true; opportunity = false; };

  check = name: lanSsh:
    let
      cfg = flake.nixosConfigurations.${name}.config;
      fw = cfg.networking.firewall;
      ssh = cfg.services.openssh;
      ts = cfg.services.tailscale;
      keys = cfg.users.users.jordangarrison.openssh.authorizedKeys.keys;
      hasKey = comment: lib.any (k: lib.hasSuffix " ${comment}" k) keys;
    in {
      firewallOn = fw.enable;
      tailnetTrusted = builtins.elem ts.interfaceName fw.trustedInterfaces;
      tailscaleDirectPath = builtins.elem ts.port fw.allowedUDPPorts;
      # Strict reverse-path filtering drops tailnet and exit-node traffic.
      reversePathLoose = fw.checkReversePath == "loose";
      forwardingNotFiltered = !fw.filterForward;
      sshEnabled = ssh.enable;
      keysOnly = ssh.settings.PasswordAuthentication == false
        && ssh.settings.KbdInteractiveAuthentication == false;
      noRootPassword = builtins.elem ssh.settings.PermitRootLogin [ "prohibit-password" "no" ];
      loginKeysPresent = lib.all hasKey loginKeys;
      sshOnLanAsIntended = ssh.openFirewall == lanSsh
        && (builtins.elem 22 fw.allowedTCPPorts) == lanSsh;
    };

  endeavour = flake.nixosConfigurations.endeavour.config;
  results = lib.mapAttrs check sshOnLan // {
    endeavourExitNode = {
      advertised = builtins.elem "--advertise-exit-node" endeavour.services.tailscale.extraSetFlags;
      routingFeatures = builtins.elem endeavour.services.tailscale.useRoutingFeatures [ "server" "both" ];
      ipv4Forwarding = endeavour.boot.kernel.sysctl."net.ipv4.conf.all.forwarding" == true;
      ipv6Forwarding = endeavour.boot.kernel.sysctl."net.ipv6.conf.all.forwarding" == true;
    };
  };
  failed = lib.concatLists (lib.mapAttrsToList (host: r:
    map (k: "${host}.${k}") (builtins.attrNames (lib.filterAttrs (_: v: !v) r))) results);
in
assert lib.assertMsg (failed == [ ]) "Remote access checks failed: ${toString failed}";
results
