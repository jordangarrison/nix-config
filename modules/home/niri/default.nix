{ config, pkgs, lib, inputs, osConfig ? null, ... }:

let
  homeDirectory = config.home.homeDirectory;
  wallpapersPath =
    "${homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/wallpapers";
  scriptsPath =
    "${homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/configs/hypr/scripts";

  # Get hostname from osConfig if available (NixOS), otherwise use null
  hostname = if osConfig != null then osConfig.networking.hostName else null;
in {
  # Packages needed for niri desktop environment
  home.packages = with pkgs; [
    # Noctalia shell (unified bar, notifications, launcher, lock screen, power menu)
    inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default

    # Notification tools (for notify-send compatibility)
    libnotify

    # Screenshot tools
    grim
    slurp
    satty

    # Clipboard
    wl-clipboard
    cliphist

    # File manager (terminal)
    yazi

    # Utilities
    brightnessctl
    playerctl
    pamixer

    # System tray applets
    networkmanagerapplet
    blueman

    # Authentication
    polkit_gnome
  ];

  # Niri configuration via programs.niri.settings
  programs.niri.settings = {
    # Prefer server-side decorations
    prefer-no-csd = true;

    # Input configuration
    input = {
      keyboard = {
        xkb = { layout = "us"; };
        repeat-delay = 300;
        repeat-rate = 50;
      };

      touchpad = {
        tap = true;
        natural-scroll = true;
        dwt = true; # Disable while typing
      };

      mouse = { accel-profile = "flat"; };

      # Focus follows mouse but don't scroll
      focus-follows-mouse = {
        enable = true;
        max-scroll-amount = "0%";
      };
    };

    # Output (monitor) configuration for endeavour
    outputs = lib.mkIf (hostname == "endeavour") {
      "DP-3" = {
        mode = {
          width = 3840;
          height = 2160;
          refresh = 60.0;
        };
        scale = 1.5;
        position = {
          x = 0;
          y = 0;
        };
      };
      "DP-4" = {
        mode = {
          width = 2560;
          height = 1440;
          refresh = 60.0;
        };
        scale = 1.333;
        position = {
          x = 2560;
          y = 0;
        };
        transform.rotation = 270; # Portrait rotation
      };
    };

    # Layout configuration
    layout = {
      gaps = 12;

      # Column widths that can be cycled through
      preset-column-widths = [
        { proportion = 1.0 / 3.0; }
        { proportion = 1.0 / 2.0; }
        { proportion = 2.0 / 3.0; }
        { proportion = 1.0; }
      ];

      # Default column width
      default-column-width = { proportion = 1.0 / 2.0; };

      # Focus ring (drawn outside windows)
      focus-ring = {
        enable = true;
        width = 2;
        active.color = "#7aa2f7";
        inactive.color = "#565f89";
      };

      # Border (drawn inside windows)
      border = { enable = false; };

      # Shadows
      shadow = { enable = true; };

      # Center focused column on screen
      center-focused-column = "always";
    };

    # Spawn programs at startup
    spawn-at-startup = [
      # Wallpaper
      {
        command = [
          "swaybg"
          "-i"
          "${wallpapersPath}/a_mountain_range_with_snow_on_top.jpeg"
          "-m"
          "fill"
        ];
      }
      # Noctalia shell (bar, notifications, launcher, lock screen, power menu)
      {
        command = [ "noctalia-shell" ];
      }
      # Clipboard manager
      {
        command = [ "wl-paste" "--watch" "cliphist" "store" ];
      }
      # Authentication agent
      {
        command = [
          "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        ];
      }
      # Network manager applet
      {
        command = [ "nm-applet" "--indicator" ];
      }
      # Bluetooth applet
      { command = [ "blueman-applet" ]; }
    ];

    # Environment variables
    environment = {
      NIXOS_OZONE_WL = "1";
      QT_QPA_PLATFORM = "wayland";
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      GDK_BACKEND = "wayland";
      MOZ_ENABLE_WAYLAND = "1";
      XDG_CURRENT_DESKTOP = "niri";
    };

    # Workspaces - all named workspaces on primary monitor (DP-3)
    # Secondary monitor (DP-4) gets dynamic workspaces only
    workspaces = {
      "1" = { open-on-output = "DP-3"; };
      "2" = { open-on-output = "DP-3"; };
      "3" = { open-on-output = "DP-3"; };
      "4" = { open-on-output = "DP-3"; };
      "5" = { open-on-output = "DP-3"; };
      "6" = { open-on-output = "DP-3"; };
      "7" = { open-on-output = "DP-3"; };
      "8" = { open-on-output = "DP-3"; };
      "9" = { open-on-output = "DP-3"; };
      "10" = { open-on-output = "DP-3"; };
    };

    # Window rules
    window-rules = [
      # Float authentication dialogs
      {
        matches = [{ app-id = "^polkit-gnome-authentication-agent-1$"; }];
        open-floating = true;
      }
      # Float file picker dialogs
      {
        matches = [{ app-id = "^xdg-desktop-portal.*$"; }];
        open-floating = true;
      }
      # Float pavucontrol
      {
        matches = [{ app-id = "^pavucontrol$"; }];
        open-floating = true;
      }
      # Float blueman
      {
        matches = [{ app-id = "^blueman-manager$"; }];
        open-floating = true;
      }
      # Float nm-connection-editor
      {
        matches = [{ app-id = "^nm-connection-editor$"; }];
        open-floating = true;
      }
    ];

    # Keybindings (matching Hyprland setup)
    binds = {
      # ==================
      # PROGRAM LAUNCHERS
      # ==================
      "Mod+Return".action.spawn = "wezterm";
      "Mod+B".action.spawn = "brave";
      "Mod+E".action.spawn = [ "emacsclient" "-c" ];
      "Mod+N".action.spawn = "obsidian";
      "Mod+F".action.spawn = [ "wezterm" "start" "--" "yazi" ];
      "Mod+Shift+F".action.spawn = "nautilus";
      "Mod+Space".action.spawn =
        [ "noctalia-shell" "ipc" "call" "launcher" "toggle" ];
      # Note: Noctalia doesn't have a built-in emoji picker, removed for now

      # ================
      # WINDOW CONTROLS
      # ================
      "Mod+Q".action.close-window = [ ];
      "Mod+V".action.toggle-window-floating = [ ];
      "Mod+M".action.maximize-column = [ ];
      "Mod+Shift+M".action.fullscreen-window = [ ];

      # ================
      # FOCUS MOVEMENT (vim-style)
      # ================
      "Mod+H".action.focus-column-left = [ ];
      "Mod+L".action.focus-column-right = [ ];
      "Mod+K".action.focus-window-up = [ ];
      "Mod+J".action.focus-window-down = [ ];

      # Arrow key alternatives
      "Mod+Left".action.focus-column-left = [ ];
      "Mod+Right".action.focus-column-right = [ ];
      "Mod+Up".action.focus-window-up = [ ];
      "Mod+Down".action.focus-window-down = [ ];

      # ================
      # WINDOW MOVEMENT
      # ================
      "Mod+Shift+H".action.move-column-left = [ ];
      "Mod+Shift+L".action.move-column-right = [ ];
      "Mod+Shift+K".action.move-window-up = [ ];
      "Mod+Shift+J".action.move-window-down = [ ];

      # Arrow key alternatives
      "Mod+Shift+Left".action.move-column-left = [ ];
      "Mod+Shift+Right".action.move-column-right = [ ];
      "Mod+Shift+Up".action.move-window-up = [ ];
      "Mod+Shift+Down".action.move-window-down = [ ];

      # ================
      # COLUMN/WINDOW SIZING
      # ================
      "Mod+Minus".action.set-column-width = "-10%";
      "Mod+Equal".action.set-column-width = "+10%";
      "Mod+Shift+Minus".action.set-window-height = "-10%";
      "Mod+Shift+Equal".action.set-window-height = "+10%";
      "Mod+R".action.switch-preset-column-width = [ ];

      # ================
      # WORKSPACES
      # ================
      "Mod+1".action.focus-workspace = 1;
      "Mod+2".action.focus-workspace = 2;
      "Mod+3".action.focus-workspace = 3;
      "Mod+4".action.focus-workspace = 4;
      "Mod+5".action.focus-workspace = 5;
      "Mod+6".action.focus-workspace = 6;
      "Mod+7".action.focus-workspace = 7;
      "Mod+8".action.focus-workspace = 8;
      "Mod+9".action.focus-workspace = 9;
      "Mod+0".action.focus-workspace = 10;

      # Move window to workspace
      "Mod+Shift+1".action.move-window-to-workspace = 1;
      "Mod+Shift+2".action.move-window-to-workspace = 2;
      "Mod+Shift+3".action.move-window-to-workspace = 3;
      "Mod+Shift+4".action.move-window-to-workspace = 4;
      "Mod+Shift+5".action.move-window-to-workspace = 5;
      "Mod+Shift+6".action.move-window-to-workspace = 6;
      "Mod+Shift+7".action.move-window-to-workspace = 7;
      "Mod+Shift+8".action.move-window-to-workspace = 8;
      "Mod+Shift+9".action.move-window-to-workspace = 9;
      "Mod+Shift+0".action.move-window-to-workspace = 10;

      # Workspace navigation
      "Mod+Page_Down".action.focus-workspace-down = [ ];
      "Mod+Page_Up".action.focus-workspace-up = [ ];
      "Mod+Shift+Page_Down".action.move-window-to-workspace-down = [ ];
      "Mod+Shift+Page_Up".action.move-window-to-workspace-up = [ ];

      # ================
      # MULTI-MONITOR
      # ================
      "Mod+Comma".action.focus-monitor-left = [ ];
      "Mod+Period".action.focus-monitor-right = [ ];
      "Mod+Shift+Comma".action.move-window-to-monitor-left = [ ];
      "Mod+Shift+Period".action.move-window-to-monitor-right = [ ];

      # ================
      # NIRI-SPECIFIC
      # ================
      "Mod+Tab".action.toggle-overview = [ ];
      "Mod+Ctrl+H".action.consume-window-into-column = [ ];
      "Mod+Ctrl+L".action.expel-window-from-column = [ ];
      "Mod+T".action.toggle-column-tabbed-display = [ ];

      # ================
      # SCREENSHOTS
      # ================
      # Region select with Satty annotation
      "Mod+Alt+S".action.spawn =
        [ "sh" "-c" "${scriptsPath}/screenshot-region-satty.sh" ];
      # Full screen with Satty annotation
      "Mod+Alt+A".action.spawn =
        [ "sh" "-c" "${scriptsPath}/screenshot-full-satty.sh" ];
      # Quick region to clipboard
      "Mod+Alt+C".action.spawn =
        [ "sh" "-c" "${scriptsPath}/screenshot-region-clipboard.sh" ];
      # Full screen to clipboard
      "Mod+Alt+F".action.spawn =
        [ "sh" "-c" "${scriptsPath}/screenshot-full-clipboard.sh" ];
      # Niri's built-in screenshot
      "Print".action.screenshot = [ ];
      "Shift+Print".action.screenshot-window = [ ];

      # ================
      # MEDIA KEYS
      # ================
      "XF86AudioRaiseVolume" = {
        allow-when-locked = true;
        action.spawn =
          [ "wpctl" "set-volume" "-l" "1.0" "@DEFAULT_AUDIO_SINK@" "5%+" ];
      };
      "XF86AudioLowerVolume" = {
        allow-when-locked = true;
        action.spawn = [ "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-" ];
      };
      "XF86AudioMute" = {
        allow-when-locked = true;
        action.spawn = [ "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle" ];
      };
      "XF86AudioMicMute" = {
        allow-when-locked = true;
        action.spawn = [ "wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle" ];
      };
      "XF86MonBrightnessUp" = {
        allow-when-locked = true;
        action.spawn = [ "brightnessctl" "-e4" "-n2" "set" "5%+" ];
      };
      "XF86MonBrightnessDown" = {
        allow-when-locked = true;
        action.spawn = [ "brightnessctl" "-e4" "-n2" "set" "5%-" ];
      };
      "XF86AudioNext" = {
        allow-when-locked = true;
        action.spawn = [ "playerctl" "next" ];
      };
      "XF86AudioPrev" = {
        allow-when-locked = true;
        action.spawn = [ "playerctl" "previous" ];
      };
      "XF86AudioPlay" = {
        allow-when-locked = true;
        action.spawn = [ "playerctl" "play-pause" ];
      };

      # ================
      # SYSTEM
      # ================
      "Mod+Ctrl+Alt+L".action.spawn =
        [ "noctalia-shell" "ipc" "call" "lock" "lock" ];
      "Mod+C".action.spawn = [ "sh" "-c" "${scriptsPath}/clipboard.sh" ];
      "Mod+Shift+C".action.spawn = [ "niri" "msg" "action" "reload-config" ];
      "Mod+Shift+Q".action.quit = [ ];
      "Mod+Shift+Slash".action.show-hotkey-overlay = [ ];
    };

    # Animations
    animations = {
      slowdown = 1.0;

      workspace-switch.kind = {
        spring = {
          damping-ratio = 1.0;
          stiffness = 1000;
          epsilon = 1.0e-4;
        };
      };

      window-open.kind = {
        easing = {
          duration-ms = 150;
          curve = "ease-out-expo";
        };
      };

      window-close.kind = {
        easing = {
          duration-ms = 150;
          curve = "ease-out-quad";
        };
      };
    };

    # Cursor configuration
    cursor = {
      theme = "Adwaita";
      size = 24;
    };

    # Hotkey overlay settings
    hotkey-overlay = { skip-at-startup = true; };

    # Screenshot configuration
    screenshot-path =
      "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png";
  };

  # Ensure screenshots directory exists
  home.file."Pictures/Screenshots/.keep".text = "";
}
