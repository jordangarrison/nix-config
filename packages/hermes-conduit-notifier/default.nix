{ fetchFromGitHub }:

# Native Hermes plugin, loaded unchanged through HERMES_HOME/plugins.
# Keep source and enablement in Nix; do not use Conduit's self-update button.
fetchFromGitHub {
  name = "hermes-conduit-notifier-0.70.2";
  owner = "kaishi00";
  repo = "hermes-conduit-notifier";
  rev = "011a7e46a99892838eccddaf7645fd2d847d56b7";
  hash = "sha256-SR12g08sUk5Vyf6u8CudATAezEVNZwsOPbHVHL7SU/c=";
}
