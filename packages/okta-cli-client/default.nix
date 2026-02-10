{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "okta-cli-client";
  version = "0.0.1";

  src = fetchFromGitHub {
    owner = "okta";
    repo = "okta-cli-client";
    rev = "v${version}";
    hash = "sha256-zFlnVGgfUcsb4hkagVYX4PXXhGGCkyg2zIBfb7CiZAc=";
  };

  vendorHash = "sha256-RQ+yYSVTDHhPokqa1taGvI64YPZXpQ6HQeFaU/hGi7c=";

  # Only build the root package; .generator/templates has broken references
  subPackages = [ "." ];

  postInstall = ''
    mv $out/bin/okta-cli-client $out/bin/okta
  '';

  meta = with lib; {
    description = "Okta CLI client for managing Okta resources";
    homepage = "https://github.com/okta/okta-cli-client";
    license = licenses.asl20;
    maintainers = [ ];
    mainProgram = "okta";
  };
}
