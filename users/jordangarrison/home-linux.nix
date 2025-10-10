{ config, pkgs, lib, username, homeDirectory, inputs, ... }:

{
  imports = [
    ./home.nix
    ../../modules/home/brave/apps.nix
    ../../modules/home/alacritty/apps.nix
    ../../modules/home/virt-manager/config.nix
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
      "mdnleldcmiljblolnjhpnblkcekpdkpa" # Requestly
      "kdfkejelgkdjgfoolngegkhkiecmlflj" # Bionic Reading
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

    "org/gnome/shell" = {
      favorite-apps = [
        "brave-browser.desktop"
        "dev.warp.WarpPreview.desktop"
        "emacsclient.desktop"
        "chatgpt.desktop"
        "todoist.desktop"
        "obsidian.desktop"
        "slack.desktop"
        "discord.desktop"
        "btop.desktop"
      ];
    };

    "org/gnome/shell/keybindings" = {
      "switch-to-application-1" = [ "<Super>b" ];
      "switch-to-application-2" = [ "<Super>w" ];
      "switch-to-application-3" = [ "<Super>c" ];
      "switch-to-application-4" = [ "<Super>g" ];
      "switch-to-application-5" = [ "<Super>t" ];
      "switch-to-application-6" = [ "<Super>n" ];
      "switch-to-application-7" = [ "<Super>u" ];
      "switch-to-application-8" = [ "<Super>d" ];
      "switch-to-application-9" = [ "<Super>q" ];
      "switch-to-application-10" = [ "" ];
    };

    "org/gnome/shell".enabled-extensions = [
      "appindicatorsupport@rgcjonas.gmail.com"
      "clipboard-history@alexsaveau.dev"
      "fuzzy-app-search@gnome-shell-extensions.gcampax.github.com"
      "gsconnect@andyholmes.github.io"
      "drive-menu@gnome-shell-extensions.gcampax.github.com"
      "auto-move-windows@gnome-shell-extensions.gcampax.github.com"
    ];

    "org/gnome/shell/extensions/auto-move-windows" = {
      application-list = [
        "brave-browser.desktop:1"
        "dev.warp.WarpPreview.desktop:2"
        "emacsclient.desktop:3"
        "todoist.desktop:5"
        "1password.desktop:10"
        "gnome-control-center.desktop:10"
        "discord.desktop:7"
        "slack.desktop:7"
      ];
    };
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

  alacrittyApps.apps = [
    {
      name = "btop";
      command = "btop";
      categories = [ "System" ];
      icon = ../../icons/btop.png;
    }
    {
      name = "sshemacs endeavour";
      command = "ssh -t endeavour 'emacsclient -nw .'";
      categories = [ "System" ];
      icon = ../../icons/btop.png;
    }
  ];

  # Enable virt-manager configuration
  virtManager = {
    enable = true;
    workspaceAssignment = 8; # Assign to workspace 8
  };

  programs.gnome-shell = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    extensions = [
      { package = pkgs.gnomeExtensions.appindicator; }
      { package = pkgs.gnomeExtensions.auto-move-windows; }
      { package = pkgs.gnomeExtensions.clipboard-history; }
      { package = pkgs.gnomeExtensions.fuzzy-app-search; }
      { package = pkgs.gnomeExtensions.gsconnect; }
      { package = pkgs.gnomeExtensions.removable-drive-menu; }
      { package = pkgs.gnomeExtensions.unite; }
    ];
  };

}
