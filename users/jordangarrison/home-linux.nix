{ config, pkgs, lib, username, homeDirectory, inputs, ... }:
{
  imports = [
    ./home.nix
    ../../modules/home/brave/apps.nix
    ../../modules/home/alacritty/apps.nix
  ];

  # Install brave.
  programs.brave =
    if pkgs.stdenv.isLinux then {
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

  braveApps.apps = [
    {
      name = "ChatGPT";
      url = "https://chat.openai.com/";
      categories = [ "Development" ];
      icon = ../../icons/chatgpt.png;
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
  ];

  # GSConnect (KDE Connect for GNOME)
  programs.gnome-shell = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    extensions = [
      { package = pkgs.gnomeExtensions.appindicator; }
      { package = pkgs.gnomeExtensions.clipboard-history; }
      { package = pkgs.gnomeExtensions.fuzzy-app-search; }
      { package = pkgs.gnomeExtensions.gsconnect; }
      { package = pkgs.gnomeExtensions.removable-drive-menu; }
    ];
  };

}
