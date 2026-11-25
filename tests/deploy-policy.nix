{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  deploy = flake.deploy;
  results = {
    explicitFleet = builtins.attrNames deploy.nodes == [ "discovery" "endeavour" "opportunity" ];
    localWorkstation = deploy.nodes.endeavour.hostname == "localhost";
    discoveryMagicDNS = deploy.nodes.discovery.hostname == "discovery";
    opportunityFQDN = deploy.nodes.opportunity.hostname == "opportunity.owl-yo.ts.net";
    noRootSSH = deploy.sshUser == "jordangarrison" && deploy.user == "root";
    noninteractiveSudo = deploy.sudo == "sudo -n -u" && !deploy.interactiveSudo;
    localBuild = !deploy.remoteBuild;
    rollbackEnabled = deploy.autoRollback && deploy.magicRollback;
    boundedTimeouts = deploy.activationTimeout == 600 && deploy.confirmTimeout == 60;
    strictSSH = builtins.elem "StrictHostKeyChecking=yes" deploy.sshOpts
      && builtins.elem "BatchMode=yes" deploy.sshOpts;
    systemProfilesOnly = lib.all (node: builtins.attrNames node.profiles == [ "system" ])
      (builtins.attrValues deploy.nodes);
    targetTrust = lib.all (name:
      builtins.elem "root" flake.nixosConfigurations.${name}.config.nix.settings.trusted-users
      && builtins.elem "jordangarrison" flake.nixosConfigurations.${name}.config.nix.settings.trusted-users
    ) [ "endeavour" "discovery" "opportunity" ];
    existingChecksRetained = flake.checks.x86_64-linux ? t3code-module
      && flake.checks.x86_64-linux ? pi-extensions;
  };
in
assert lib.assertMsg (lib.all (x: x) (builtins.attrValues results)) "Deploy policy checks failed";
results
