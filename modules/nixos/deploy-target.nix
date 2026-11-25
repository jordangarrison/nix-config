# Imported only by the explicit NixOS deploy targets in flake.nix.
# deploy-rs copies locally built, unsigned closures over Jordan's SSH session.
# Nix trust is root-equivalent; Jordan already has unrestricted NOPASSWD sudo.
{ ... }:
{
  nix.settings.trusted-users = [ "root" "jordangarrison" ];
}
