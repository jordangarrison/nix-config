{ ... }:

{
  # Overlay to make script packages available via pkgs.<name>
  nixpkgs.overlays = [
    (final: prev: let
      mkScript = final.callPackage ../lib/mkScript.nix { };
    in {
      myip = mkScript {
        name = "myip";
        script = ../packages/myip/myip.sh;
        deps = with final; [ curl jq ];
        description = "Display public IP with geolocation info";
      };

      gi = mkScript {
        name = "gi";
        script = ../packages/gi/gi.sh;
        deps = with final; [ curl ];
        description = "Fetch gitignore templates from gitignore.io";
      };

      tmux-cht = mkScript {
        name = "tmux-cht";
        script = ../packages/tmux-cht/tmux-cht.sh;
        deps = with final; [ tmux fzf curl less gnugrep ];
        description = "Cheat sheet lookup in tmux window";
      };

      ksn = mkScript {
        name = "ksn";
        script = ../packages/ksn/ksn.sh;
        deps = with final; [ kubectl ];
        description = "Switch kubectl namespace";
      };

      claude-switch = mkScript {
        name = "claude-switch";
        script = ../packages/claude-switch/claude-switch.sh;
        deps = with final; [ coreutils gnused ];
        description = "Switch between Claude Code credential profiles";
      };
    })
  ];
}
