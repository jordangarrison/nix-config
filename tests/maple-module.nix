# nix eval --json --impure --expr 'import ./tests/maple-module.nix { flake = builtins.getFlake (toString ./.); }'
{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  cfg = flake.nixosConfigurations.endeavour.config;
  service = cfg.systemd.services.maple;
  proxy = cfg.services.nginx.virtualHosts."maple.jordangarrison.dev";
  guard = proxy.locations."/".extraConfig;
  mount = lib.findFirst (m: m.where == "/var/lib/maple") null cfg.systemd.mounts;
  results = {
    enabled = cfg.services.maple.enable;
    upstreamBinaryVersion = cfg.services.maple.package.version == "0.3.5";
    loopbackOnly = cfg.services.maple.host == "127.0.0.1";
    noFirewallPort = !cfg.services.maple.openFirewall && !(lib.elem 4318 cfg.networking.firewall.allowedTCPPorts);
    privateCredentials = service.serviceConfig.LoadCredential == [
      "ingest-key:/var/lib/maple-secrets/ingest-key"
      "access-token:/var/lib/maple-secrets/access-token"
    ];
    secretOrdering = lib.elem "maple-secrets.service" service.requires && lib.elem "maple-secrets.service" service.after;
    secretDirectoryPrivate = cfg.systemd.services.maple-secrets.serviceConfig.StateDirectoryMode == "0700";
    secretFilePermissions = lib.hasInfix "chmod 0600" cfg.systemd.services.maple-secrets.script;
    mountRequired = service.unitConfig.RequiresMountsFor == "/var/lib/maple";
    stateOnGemini = mount.what == "/mnt/gemini/maple" && mount.type == "none";
    mountOrdering = lib.elem "mnt-gemini.mount" mount.requires
      && lib.elem "maple-state-directory.service" mount.requires
      && lib.elem "maple-state-directory.service" mount.after;
    stopOnDriveLoss = lib.elem "mnt-gemini.mount" mount.bindsTo;
    directoryAfterMount = lib.elem "mnt-gemini.mount" cfg.systemd.services.maple-state-directory.requires
      && lib.hasInfix "mountpoint -q /mnt/gemini" cfg.systemd.services.maple-state-directory.script;
    bootWithoutDrive = lib.elem "nofail" cfg.fileSystems."/mnt/gemini".options
      && lib.elem "x-systemd.device-timeout=5s" cfg.fileSystems."/mnt/gemini".options;
    correctFilesystem = cfg.fileSystems."/mnt/gemini".device == "/dev/disk/by-uuid/daefadb8-2bb3-4073-8fb8-d4820021506a"
      && cfg.fileSystems."/mnt/gemini".fsType == "ext4";
    agentsviewOnGemini = cfg.systemd.services.agentsview.environment.AGENTSVIEW_DATA_DIR == "/mnt/gemini/agentsview";
    agentsviewRequiresMount = cfg.systemd.services.agentsview.unitConfig.RequiresMountsFor == "/mnt/gemini";
    agentsviewDirectoryPrivate = lib.elem "d /mnt/gemini/agentsview 0700 jordangarrison users - -" cfg.systemd.tmpfiles.rules;
    agentsviewDirectoryOrdering = lib.elem "mnt-gemini.mount" cfg.systemd.services.agentsview-state-directory.requires
      && lib.elem "agentsview-state-directory.service" cfg.systemd.services.agentsview.requires;
    noLoopbackProvisioner = !(cfg.systemd.services ? maple-volume);
    noAutomaticWipe = cfg.services.maple.onDirtyStore == "fail";
    defaultRetention = cfg.services.maple.extraArgs == [ ];
    checkpointsEnabled = cfg.services.maple.checkpointInterval == "30m";
    https = proxy.forceSSL && proxy.useACMEHost == "maple.jordangarrison.dev";
    sharedListenersPreserved = proxy.listen == [ ];
    correctBackend = proxy.locations."/".proxyPass == "http://127.0.0.1:4318";
    singleIngestAndUiProxy = lib.attrNames proxy.locations == [ "/" ];
    tailnetOnly = lib.hasInfix "allow 100.64.0.0/10;" guard
      && lib.hasInfix "allow fd7a:115c:a1e0::/48;" guard
      && lib.hasInfix "deny all;" guard;
    certOwnedByNginx = cfg.security.acme.certs."maple.jordangarrison.dev".group == "nginx";
    otherLinuxHostsUnchanged = lib.all (name: !(flake.nixosConfigurations.${name}.config.services ? maple)) [
      "opportunity" "discovery"
    ];
  };
in
assert lib.assertMsg (lib.all (x: x) (lib.attrValues results))
  "Maple module checks failed: ${lib.concatStringsSep ", " (lib.attrNames (lib.filterAttrs (_: result: !result) results))}";
results
