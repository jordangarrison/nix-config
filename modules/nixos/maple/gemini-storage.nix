{ pkgs, ... }:

let
  # Storage placement lives here. The upstream service keeps HOME and all
  # store sidecars at /var/lib/maple through the bind mount below.
  stateDir = "/mnt/gemini/maple";
in
{
  systemd.services.maple-state-directory = {
    description = "Prepare Maple state on the mounted Gemini drive";
    requires = [ "mnt-gemini.mount" ];
    after = [ "mnt-gemini.mount" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      # Never create a fallback store on / if the physical drive is absent.
      ${pkgs.util-linux}/bin/mountpoint -q /mnt/gemini
      ${pkgs.coreutils}/bin/install -d -m 0700 -o maple -g maple ${stateDir}
    '';
  };

  systemd.mounts = [
    {
      what = stateDir;
      where = "/var/lib/maple";
      type = "none";
      options = "bind,nodev,nosuid,noexec";
      requires = [ "mnt-gemini.mount" "maple-state-directory.service" ];
      after = [ "mnt-gemini.mount" "maple-state-directory.service" ];
      bindsTo = [ "mnt-gemini.mount" ];
      mountConfig.DirectoryMode = "0700";
    }
  ];
}
