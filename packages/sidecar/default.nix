{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "sidecar";
  version = "0.71.1";

  src = fetchFromGitHub {
    owner = "marcus";
    repo = "sidecar";
    rev = "v${version}";
    hash = "sha256-LqpqNQ56tKXqEKbUrMxBkiGOzklGaqx8SCTEGIwE43k=";
  };

  vendorHash = "sha256-R/AjNJ4x4t1zXXzT+21cjY+9pxs4DVXU4xs88BQvHx4=";

  subPackages = [ "./cmd/sidecar" ];

  ldflags = [
    "-X main.Version=v${version}"
  ];

  meta = with lib; {
    description = "TUI companion for CLI coding agents — diffs, file trees, conversation history, and task management";
    homepage = "https://github.com/marcus/sidecar";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "sidecar";
  };
}
