{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.gbg-config.remote-builders;
in
{
  options.gbg-config.remote-builders = {
    enable = mkEnableOption "Enable remote builder support";

    sshKeyPath = mkOption {
      type = types.path;
      default = "/home/jordangarrison/.ssh/id_ed25519";
      description = "Path to the SSH private key used for remote builds.";
    };

    builderHost = mkOption {
      type = types.str;
      default = "endeavour";
      description = "Hostname or IP of the remote builder machine.";
    };

    builderUser = mkOption {
      type = types.str;
      default = "jordangarrison";
      description = "SSH username to connect to the builder.";
    };

    system = mkOption {
      type = types.str;
      default = "x86_64-linux";
      description = "System platform identifier for the builder (e.g. x86_64-linux, aarch64-linux).";
    };

    maxJobs = mkOption {
      type = types.int;
      default = 24;
      description = "Maximum number of jobs the builder can run.";
    };

    speedFactor = mkOption {
      type = types.int;
      default = 10;
      description = "Relative build speed of the remote builder.";
    };

    supportedFeatures = mkOption {
      type = types.listOf types.str;
      default = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
      description = "Features supported by the remote builder.";
    };
  };

  config = mkIf cfg.enable {
    nix.settings = {
      builders-use-substitutes = true;
      trusted-users = [ "jordangarrison" "root" "jordan" ];
      max-jobs = 1; # Allow local fallback if remote builder fails
    };

    nix.distributedBuilds = true;

    nix.buildMachines = [
      {
        hostName = cfg.builderHost;
        system = cfg.system;
        sshUser = cfg.builderUser;
        sshKey = cfg.sshKeyPath;
        maxJobs = cfg.maxJobs;
        speedFactor = cfg.speedFactor;
        supportedFeatures = cfg.supportedFeatures;
      }
    ];
  };
}
