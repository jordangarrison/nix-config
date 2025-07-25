{ config, pkgs, lib, username, homeDirectory, inputs, ... }:

{
  imports = [
    ./home.nix
    ../../modules/home/brave/apps.nix
    ../../modules/home/alacritty/apps.nix
  ];

  # Install brave.
  programs.brave = if pkgs.stdenv.isLinux then {
    enable = true;
    extensions = [
      "aeblfdkhhhdcdjpifhhbdiojplfjncoa" # 1Password
      "eimadpbcbfnmbkopoojfekhnkhdbieeh" # Dark Reader
      "bcjindcccaagfpapjjmafapmmgkkhgoa" # JSON Formatter
      "cnjifjpddelmedmihgijeibhnjfabmlf" # Obsidian Web Clipper
      "glnpjglilkicbckjpbgcfkogebgllemb" # Okta Browser Plugin
      "jjhefcfhmnkfeepcpnilbbkaadhngkbi" # Readwise Highlighter
      "gmbmikajjgmnabiglmofipeabaddhgne" # Save to Google Drive
      "micdllihgoppmejpecmkilggmaagfdmb" # Tab Copy
      "egnjhciaieeiiohknchakcodbpgjnchh" # Tab Wrangler
      "jldhpllghnbhlbpcmnajkpdmadaolakh" # Todoist for Chrome
      "clgenfnodoocmhnlnpknojdbjjnmecff" # Todoist for Gmail
    ];
  } else {
    enable = false;
  };

  dconf.settings = {
    # Fixed number of workspaces
    "org/gnome/mutter" = { dynamic-workspaces = false; };
    "org/gnome/desktop/wm/preferences" = { num-workspaces = 10; };

    # Keybindings to switch to workspace
    "org/gnome/desktop/wm/keybindings" = {
      "switch-to-workspace-1" = [ "<Super>1" ];
      "switch-to-workspace-2" = [ "<Super>2" ];
      "switch-to-workspace-3" = [ "<Super>3" ];
      "switch-to-workspace-4" = [ "<Super>4" ];
      "switch-to-workspace-5" = [ "<Super>5" ];
      "switch-to-workspace-6" = [ "<Super>6" ];
      "switch-to-workspace-7" = [ "<Super>7" ];
      "switch-to-workspace-8" = [ "<Super>8" ];
      "switch-to-workspace-9" = [ "<Super>9" ];
      "switch-to-workspace-10" = [ "<Super>0" ];

      # Optional: move current window to workspace
      "move-to-workspace-1" = [ "<Shift><Super>1" ];
      "move-to-workspace-2" = [ "<Shift><Super>2" ];
      "move-to-workspace-3" = [ "<Shift><Super>3" ];
      "move-to-workspace-4" = [ "<Shift><Super>4" ];
      "move-to-workspace-5" = [ "<Shift><Super>5" ];
      "move-to-workspace-6" = [ "<Shift><Super>6" ];
      "move-to-workspace-7" = [ "<Shift><Super>7" ];
      "move-to-workspace-8" = [ "<Shift><Super>8" ];
      "move-to-workspace-9" = [ "<Shift><Super>9" ];
      "move-to-workspace-10" = [ "<Shift><Super>0" ];
    };
    "org/gnome/shell/keybindings" = {
      "switch-to-application-1" = [ ];
      "switch-to-application-2" = [ ];
      "switch-to-application-3" = [ ];
      "switch-to-application-4" = [ ];
      "switch-to-application-5" = [ ];
      "switch-to-application-6" = [ ];
      "switch-to-application-7" = [ ];
      "switch-to-application-8" = [ ];
      "switch-to-application-9" = [ ];
      "switch-to-application-10" = [ ];
    };

    "org/gnome/shell".enabled-extensions = [
      "appindicatorsupport@rgcjonas.gmail.com"
      "clipboard-history@alexsaveau.dev"
      "fuzzy-app-search@gnome-shell-extensions.gcampax.github.com"
      "gsconnect@andyholmes.github.io"
      "drive-menu@gnome-shell-extensions.gcampax.github.com"
      "auto-move-windows@gnome-shell-extensions.gcampax.github.com"
    ];
  };

  braveApps.apps = [
    {
      name = "ChatGPT";
      url = "https://chat.openai.com/";
      categories = [ "Development" ];
      icon = ../../icons/chatgpt.png;
    }
    {
      name = "Google Meet";
      url = "https://meet.google.com/";
      categories = [ "AudioVideo" ];
      icon = ../../icons/google-meet.png;
    }
    {
      name = "YouTube";
      url = "https://www.youtube.com/";
      categories = [ "AudioVideo" ];
      icon = ../../icons/youtube.png;
    }
  ];

  alacrittyApps.apps = [{
    name = "btop";
    command = "btop";
    categories = [ "System" ];
    icon = ../../icons/btop.png;
  }];

  # GSConnect (KDE Connect for GNOME)
  programs.gnome-shell = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    extensions = [
      { package = pkgs.gnomeExtensions.appindicator; }
      { package = pkgs.gnomeExtensions.auto-move-windows; }
      { package = pkgs.gnomeExtensions.clipboard-history; }
      { package = pkgs.gnomeExtensions.fuzzy-app-search; }
      { package = pkgs.gnomeExtensions.gsconnect; }
      { package = pkgs.gnomeExtensions.removable-drive-menu; }
    ];
  };

}
