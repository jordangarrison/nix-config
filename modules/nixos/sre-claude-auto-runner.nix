{ inputs, pkgs, ... }:

{
  imports = [ inputs.sre-claude-auto-runner.nixosModules.default ];

  services.sre-claude-auto-runner = {
    enable = true;
    user = "jordangarrison";
    workspaceDir = "/home/jordangarrison/dev/flocasts";
    dryRun = false;
    maxParallel = 1;
    path = with pkgs; [ claude-code gh jira-cli-go git ];
  };
}
