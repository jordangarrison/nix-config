{ config, pkgs, lib, ... }:

let
  homeDirectory = config.home.homeDirectory;
  scriptsPath = "${homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/configs/hypr/scripts";

  # Helper to create a menu entry
  entry = key: desc: cmd: { inherit key desc cmd; };
  submenu = key: desc: items: { inherit key desc; submenu = items; };

  menuConfig = {
    # Theming
    font = "JetBrainsMono Nerd Font 12";
    background = "#282828d0";
    color = "#fbf1c7";
    border = "#8ec07c";
    separator = " -> ";
    border_width = 2;
    corner_r = 10;
    padding = 15;
    anchor = "center";

    menu = [
      # [p] Power
      (submenu "p" "Power" [
        (entry "s" "Suspend" "systemctl suspend")
        (entry "r" "Reboot" "systemctl reboot")
        (entry "o" "Shutdown" "systemctl poweroff")
        (entry "l" "Lock Screen" "noctalia-shell ipc call lockScreen lock")
      ])

      # [s] Screenshots
      (submenu "s" "Screenshots" [
        (entry "r" "Region -> Annotate" "${scriptsPath}/screenshot-region-satty.sh")
        (entry "s" "Screen -> Annotate" "${scriptsPath}/screenshot-focused-monitor-satty.sh")
        (entry "w" "Window -> Annotate" "${scriptsPath}/screenshot-window-satty.sh")
        (entry "c" "Region -> Clipboard" "${scriptsPath}/screenshot-region-clipboard.sh")
        (entry "f" "Screen -> Clipboard" "${scriptsPath}/screenshot-focused-monitor-clipboard.sh")
        (entry "a" "All Monitors -> Annotate" "${scriptsPath}/screenshot-full-satty.sh")
        (entry "A" "All Monitors -> Clipboard" "${scriptsPath}/screenshot-full-clipboard.sh")
      ])

      # [a] Apps
      (submenu "a" "Apps" [
        (submenu "a" "AI Tools" [
          (entry "c" "Claude" "brave --app=https://claude.ai")
          (entry "g" "ChatGPT" "brave --app=https://chat.openai.com")
          (entry "m" "Gemini" "brave --app=https://gemini.google.com")
        ])
        (submenu "s" "System" [
          (entry "b" "btop" "alacritty -e btop")
          (entry "n" "Network" "alacritty -e nmtui")
        ])
        (submenu "m" "Media" [
          (entry "o" "OBS Studio" "obs")
        ])
      ])

      # [w] Web
      (submenu "w" "Web" [
        (submenu "m" "Mail" [
          (entry "p" "Personal Gmail" "brave https://mail.google.com/mail/u/0/#inbox")
          (entry "w" "Work Gmail" "brave https://mail.google.com/mail/u/1/#inbox")
          (entry "f" "Family Gmail" "brave https://mail.google.com/mail/u/2/#inbox")
          (entry "i" "iCloud Mail" "brave https://icloud.com/mail")
        ])
        (submenu "g" "GitHub" [
          (submenu "p" "Personal" [
            (entry "p" "Profile" "brave https://github.com/jordangarrison")
            (entry "n" "Nix Config" "brave https://github.com/jordangarrison/nix-config")
          ])
          (submenu "f" "Flocasts" [
            (entry "o" "Org" "brave https://github.com/flocasts")
            (entry "i" "Infra Base Services" "brave https://github.com/flocasts/infra-base-services")
            (entry "w" "Web Monorepo" "brave https://github.com/flocasts/web-monorepo")
            (entry "t" "Teams" "brave https://github.com/orgs/flocasts/teams")
          ])
          (submenu "e" "Enterprise" [
            (entry "d" "Dashboard" "brave https://github.com/enterprises/flosports/")
            (entry "p" "People" "brave https://github.com/enterprises/flosports/people")
            (entry "a" "AI Controls" "brave https://github.com/enterprises/flosports/ai-controls/agents")
          ])
        ])
        (entry "j" "Jira Board" "brave https://flocasts.atlassian.net/jira/software/c/projects/INFRA/boards/166")
        (entry "c" "Calendar" "brave https://calendar.google.com/calendar/u/1/r/week")
        (entry "t" "Meet" "brave --app=https://meet.google.com")
      ])

      # [m] Media
      (submenu "m" "Media" [
        (entry "h" "Headphones" "pactl set-default-sink $(pactl list short sinks | grep -i headphone | head -1 | cut -f2)")
        (entry "s" "Speakers" "pactl set-default-sink $(pactl list short sinks | grep -iv headphone | grep -iv monitor | head -1 | cut -f2)")
        (entry "m" "Toggle Mic Mute" "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")
      ])

      # [x] Session
      (submenu "x" "Session" [
        (entry "r" "Reload Config" "niri msg action reload-config")
        (entry "q" "Quit Niri" "niri msg action quit")
        (entry "h" "Hotkey Overlay" "niri msg action show-hotkey-overlay")
      ])

      # [d] Display
      (submenu "d" "Display" [
        (entry "h" "Focus Monitor Left" "niri msg action focus-monitor-left")
        (entry "l" "Focus Monitor Right" "niri msg action focus-monitor-right")
        (entry "H" "Move to Monitor Left" "niri msg action move-window-to-monitor-left")
        (entry "L" "Move to Monitor Right" "niri msg action move-window-to-monitor-right")
      ])
    ];
  };

  configFile = pkgs.writeText "wlr-which-key-config.yaml" (builtins.toJSON menuConfig);

  whichKeyMenu = pkgs.writeShellScriptBin "wlr-which-key-menu" ''
    exec ${pkgs.wlr-which-key}/bin/wlr-which-key ${configFile}
  '';
in
{
  home.packages = [
    pkgs.wlr-which-key
    whichKeyMenu
  ];
}
