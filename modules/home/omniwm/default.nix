# OmniWM: Niri-style scrolling tiling on macOS, set up with the same flow as
# modules/home/niri. Read ./README.md before changing it: the settings
# schema is strict, and OmniWM rejects the whole file on one bad key.
{
  lib,
  userApps ? { },
  ...
}:

let
  # Mod key. OmniWM's "Hyper" is a modifier set that one physical key
  # produces while held. Right Command acts as Option+Command here. Control
  # and Shift stay out of the set, so Mod+Ctrl and Mod+Shift are distinct
  # chords, the same as on niri.
  hyperTrigger = "Right Command";
  modMods = [
    "Option"
    "Command"
  ];

  # OmniWM writes modifiers in this order.
  modifierOrder = [
    "Control"
    "Option"
    "Shift"
    "Command"
  ];
  modsWith =
    extraMods:
    let
      mods = modMods ++ extraMods;
    in
    lib.concatStringsSep "+" (lib.filter (m: lib.elem m mods) modifierOrder);
  chord = extraMods: key: "${modsWith extraMods}+${key}";

  mod = modsWith [ ];
  modShift = modsWith [ "Shift" ];
  modCtrl = modsWith [ "Control" ];

  # Every hotkey action id in OmniWM 0.7.4 (ActionCatalog). Version 4 of the
  # schema needs each id exactly once. The ".9" workspace ids are optional
  # and exist because workspace 10 is defined below. Update this list when
  # nixpkgs moves OmniWM to a release that adds or removes actions.
  range = from: to: map toString (lib.range from to);
  hotkeyIds = lib.concatLists [
    (lib.concatMap (n: [
      "toggleScratchpad.${n}"
      "assignFocusedWindowToScratchpad.${n}"
    ]) (range 1 10))
    (lib.concatMap (n: [
      "switchWorkspace.${n}"
      "moveToWorkspace.${n}"
    ]) (range 0 9))
    (lib.concatMap (n: [
      "switchWorkspaceSlot.${n}"
      "moveToWorkspaceSlot.${n}"
    ]) (range 1 9))
    [
      "workspaceBackAndForth"
      "switchWorkspace.next"
      "switchWorkspace.previous"
      "focus.left"
      "focus.down"
      "focus.up"
      "focus.right"
      "focusPrevious"
      "focusDownOrLeft"
      "focusUpOrRight"
      "focusWindowTop"
      "focusWindowBottom"
      "focusWindowDownOrTop"
      "focusWindowUpOrBottom"
      "focusWindowOrWorkspaceDown"
      "focusWindowOrWorkspaceUp"
      "centerColumn"
      "centerVisibleColumns"
      "moveWindowToWorkspaceUp"
      "moveWindowToWorkspaceDown"
      "moveColumnToWorkspaceUp"
      "moveColumnToWorkspaceDown"
    ]
    (map (n: "moveColumnToWorkspace.${n}") (range 0 9))
    [
      "move.left"
      "move.down"
      "move.up"
      "move.right"
      "moveWindowDown"
      "moveWindowUp"
      "moveWindowDownOrToWorkspaceDown"
      "moveWindowUpOrToWorkspaceUp"
      "consumeWindowIntoColumn"
      "expelWindowFromColumn"
      "focusMonitorNext"
      "focusMonitorPrevious"
      "focusMonitorLast"
      "moveWorkspaceToMonitor.left"
      "moveWorkspaceToMonitor.right"
      "moveWorkspaceToMonitor.up"
      "moveWorkspaceToMonitor.down"
      "moveWindowToMonitor.left"
      "moveWindowToMonitor.right"
      "moveWindowToMonitor.up"
      "moveWindowToMonitor.down"
      "toggleFullscreen"
      "toggleNativeFullscreen"
      "moveColumn.left"
      "moveColumn.right"
      "moveColumn.up"
      "moveColumn.down"
      "moveColumnToFirst"
      "moveColumnToLast"
      "toggleColumnTabbed"
      "focusColumnFirst"
      "focusColumnLast"
    ]
    (map (n: "focusColumn.${n}") (range 0 8))
    (map (n: "focusWindowInColumn.${n}") (range 1 9))
    (map (n: "moveColumnToIndex.${n}") (range 1 9))
    [
      "cycleSizeForward"
      "cycleSizeBackward"
      "cycleWindowPrimarySpanForward"
      "cycleWindowPrimarySpanBackward"
      "cycleWindowSecondarySpanForward"
      "cycleWindowSecondarySpanBackward"
      "toggleContainerFullPrimarySpan"
      "expandContainerToAvailablePrimarySpan"
      "resetWindowSecondarySpan"
      "setContainerPrimarySpan.decrease10Percent"
      "setContainerPrimarySpan.increase10Percent"
      "setWindowPrimarySpan.decrease10Percent"
      "setWindowPrimarySpan.increase10Percent"
      "setWindowSecondarySpan.decrease10Percent"
      "setWindowSecondarySpan.increase10Percent"
      "balanceSizes"
      "moveToRoot"
      "toggleSplit"
      "swapSplit"
      "resizeGrow.horizontal"
      "resizeGrow.vertical"
      "resizeShrink.horizontal"
      "resizeShrink.vertical"
      "resizeFocusedWindow.grow"
      "resizeFocusedWindow.shrink"
      "preselect.left"
      "preselect.right"
      "preselect.up"
      "preselect.down"
      "preselectClear"
      "openCommandPalette"
      "raiseAllFloatingWindows"
      "rescueOffscreenWindows"
      "toggleFocusedWindowFloating"
      "closeFocusedWindow"
      "openMenuAnywhere"
      "setWindowMark"
      "removeWindowMark"
      "toggleWorkspaceBarVisibility"
      "toggleHiddenBarPanel"
      "toggleQuakeTerminal"
      "toggleWorkspaceLayout"
      "toggleOverview"
      "toggleSystemStats"
    ]
  ];

  # Niri binds (modules/home/niri/default.nix) mapped to OmniWM actions.
  # Every other action is Unassigned, so OmniWM's Option defaults do not
  # take keys from Emacs and other apps. OmniWM has no spawn action, so the
  # app launchers (Mod+Return, Mod+B, Mod+E, ...) are not here.
  niriFlow =
    let
      digit = n: if n == 10 then "0" else toString n;
      workspaceBinds = lib.listToAttrs (
        lib.concatMap (n: [
          (lib.nameValuePair "switchWorkspace.${toString (n - 1)}" (chord [ ] (digit n)))
          (lib.nameValuePair "moveToWorkspace.${toString (n - 1)}" (chord [ "Shift" ] (digit n)))
        ]) (lib.range 1 10)
      );
    in
    workspaceBinds
    // {
      # Window controls
      "closeFocusedWindow" = "${mod}+Q";
      "toggleFocusedWindowFloating" = "${mod}+V";
      "toggleContainerFullPrimarySpan" = "${mod}+M"; # maximize-column
      "toggleFullscreen" = "${modShift}+M";

      # Focus (vim keys). OmniWM gives each action one binding, so the
      # niri arrow-key duplicates are dropped.
      "focus.left" = "${mod}+H";
      "focus.right" = "${mod}+L";
      "focus.down" = "${mod}+J";
      "focus.up" = "${mod}+K";

      # Move. OmniWM's "move.left/right" consumes or expels across columns;
      # niri's Mod+Shift+H/L moves the whole column, which is moveColumn.
      "moveColumn.left" = "${modShift}+H";
      "moveColumn.right" = "${modShift}+L";
      "moveWindowDown" = "${modShift}+J";
      "moveWindowUp" = "${modShift}+K";

      # Column membership and display
      "consumeWindowIntoColumn" = "${modCtrl}+H";
      "expelWindowFromColumn" = "${modCtrl}+L";
      "toggleColumnTabbed" = "${mod}+T";
      "centerColumn" = "${mod}+G";

      # Sizing (step is niri.resizeStepPercent below)
      "setContainerPrimarySpan.decrease10Percent" = "${mod}+Minus";
      "setContainerPrimarySpan.increase10Percent" = "${mod}+Equal";
      "setWindowSecondarySpan.decrease10Percent" = "${modShift}+Minus";
      "setWindowSecondarySpan.increase10Percent" = "${modShift}+Equal";
      "cycleSizeForward" = "${mod}+R"; # switch-preset-column-width

      # Workspaces up and down
      "switchWorkspace.next" = "${mod}+Page Down";
      "switchWorkspace.previous" = "${mod}+Page Up";
      "moveWindowToWorkspaceDown" = "${modShift}+Page Down";
      "moveWindowToWorkspaceUp" = "${modShift}+Page Up";

      # Monitors
      "focusMonitorPrevious" = "${mod}+Comma";
      "focusMonitorNext" = "${mod}+Period";
      "moveWindowToMonitor.left" = "${modShift}+Comma";
      "moveWindowToMonitor.right" = "${modShift}+Period";

      # Overview, command menu, terminal
      "toggleOverview" = "${mod}+Tab";
      "openCommandPalette" = "${mod}+D"; # stands in for the which-key menu
      "toggleQuakeTerminal" = "${mod}+Grave";
    };

  unknownBinds = lib.subtractLists hotkeyIds (lib.attrNames niriFlow);
  duplicateIds = lib.subtractLists (lib.unique hotkeyIds) hotkeyIds;

  hotkeys = map (id: {
    inherit id;
    binding = niriFlow.${id} or "Unassigned";
  }) hotkeyIds;

  color = r: g: b: a: {
    red = r;
    green = g;
    blue = b;
    alpha = a;
  };
  hex = n: n / 255.0;
  # Rose Pine Foam (#9ccfd8), the niri focus-ring color.
  foam = color (hex 156) (hex 207) (hex 216) 1.0;

  # Stable workspace ids. Do not change them; OmniWM keys state on them.
  workspaceIds = [
    "E99E0D32-3680-4653-A937-2F87E2355552"
    "49A5251F-0034-4232-87AB-51233A20D0E8"
    "30893773-140B-407A-8D07-45167BC0F4BE"
    "8F6B0E3F-E0E3-42C8-B8E3-480CA9BA82EE"
    "4F244068-3C3B-4CC9-B99D-3A422C9D762A"
    "81F8ED74-FED2-4264-A290-1D5AAF7AC366"
    "44443F2D-D68C-4D39-A82D-B39671B23238"
    "D714384F-7D0E-4C34-90C5-F752C6A520BB"
    "C6318F4A-E883-479C-9E7E-9D2BFC70929C"
    "640A1C51-F4EF-4FA3-8A69-F59190429CBB"
  ];

  # OmniWM's built-in minimum-size rules (BuiltInSettingsDefaults.swift).
  # A managed appRules array replaces them, so they are repeated here.
  minSizeRule = bundleId: minWidth: minHeight: { inherit bundleId minWidth minHeight; };

  settings = {
    schemaVersion = 4;

    general = {
      hotkeysEnabled = true;
      systemHyperTrigger = hyperTrigger;
      hyperKeyModifiers = lib.concatStringsSep "+" modMods;
      defaultLayoutType = "niri";
      preventSleepEnabled = false;
      updateChecksEnabled = false; # nixpkgs owns the version
      ipcEnabled = true; # for omniwmctl
      animationsEnabled = true;
    };

    focus = {
      followsMouse = true; # niri focus-follows-mouse
      raiseOnMouseFocus = false;
      lockModifier = "off";
      moveMouseToFocusedWindow = false;
      followsWindowToMonitor = false;
      crossesMonitorAtEdge = false;
      moveCrossesMonitorAtEdge = false;
    };

    mouseWarp = {
      margin = 1;
      enabled = true;
      constrainToArrangement = false;
    };

    routing = {
      mode = "macOS";
      arrangements = [ ];
    };

    # niri: gaps = 8 on every side. edgeGaps keeps the inner gap at the
    # left and right screen edges; outer top/bottom add the rest.
    gaps = {
      size = 8.0;
      fullscreenUsesOuterGaps = false;
      outer = {
        left = 0.0;
        right = 0.0;
        top = 8.0;
        bottom = 8.0;
      };
    };

    niri = {
      visibleContainerCount = 2;
      infiniteLoop = false;
      centerFocusedColumn = "onOverflow";
      alwaysCenterSingleColumn = false;
      # A lone window keeps its column width, as on niri.
      singleWindowFit = "container_primary_span";
      containerPrimarySpanPresets = [
        (1.0 / 3.0)
        0.5
        (2.0 / 3.0)
        1.0
      ];
      defaultContainerPrimarySpan = 0.5;
      resizeStepPercent = 10;
      edgeGaps = true;
    };

    dwindle = {
      smartSplit = false;
      defaultSplitRatio = 1.0;
      splitWidthMultiplier = 1.0;
      singleWindowFit = "fill";
      useGlobalGaps = true;
      moveToRootStable = true;
    };

    borders = {
      enabled = true;
      width = 2.0;
      color = foam;
    };

    overview = {
      zoom = 1.0;
      backdrop = color 0.05 0.05 0.08 1.0;
      windowBorders = {
        normal = color 0.3 0.3 0.35 0.5;
        hovered = color 0.4 0.6 1.0 1.0;
        selected = foam;
      };
    };

    workspaceBar = {
      enabled = true;
      showLabels = true;
      showFloatingWindows = false;
      windowLevel = "popup";
      position = "overlappingMenuBar";
      notchMode = "moveBelowMenuBar";
      notchActiveZoneWidth = 180.0;
      systemStatsButton = false;
      deduplicateAppIcons = false;
      hideEmptyWorkspaces = true;
      excludedBundleIDs = [ ];
      iconOverrides = { };
      reserveLayoutSpace = false;
      revealModifier = "off";
      revealHoldMilliseconds = 200.0;
      hideInNativeFullscreen = false;
      height = 24.0;
      backgroundOpacity = 0.1;
      xOffset = 0.0;
      yOffset = 0.0;
    };

    gestures = {
      scrollEnabled = true;
      scrollSensitivity = 5.0;
      scrollModifierKey = "optionShift";
      mouseMoveModifierKey = "option";
      mouseResizeModifierKey = "option";
      fingerCount = 3;
      invertDirection = true;
      trackpadScrollStyle = "snap";
      workspaceSwipeEnabled = false;
      workspaceSwipeFingerCount = 3;
      workspaceSwipeAxis = "vertical";
    };

    statusBar = {
      showWorkspaceName = false;
      showAppNames = false;
      useWorkspaceId = false;
    };

    hiddenBar = {
      enabled = true;
      hiddenBundleIDs = [ ];
      rehideIntervalSeconds = 5.0;
    };

    clipboard = {
      historyEnabled = false;
      maxItems = 200;
      maxItemBytes = 8388608;
      maxTotalBytes = 67108864;
      ignoredTypes = [ ];
    };

    quakeTerminal = {
      enabled = true;
      position = "center";
      widthPercent = 50.0;
      heightPercent = 50.0;
      animationDuration = 0.2;
      autoHide = false;
      backgroundEffect = "standardBlur";
    };

    scratchpads.labels = { };

    appearance.mode = "dark";

    inherit hotkeys;

    # Workspaces 1-10 on the main display, all Niri, as on niri.
    workspaces = lib.imap1 (n: id: {
      inherit id;
      name = toString n;
      layoutType = "niri";
      monitorAssignment.type = "main";
    }) workspaceIds;

    appRules = [
      (minSizeRule "com.openai.codex" 800.0 600.0)
      (minSizeRule "com.eltima.cmd1.pro.mas" 950.0 550.0)
      (minSizeRule "com.google.Chrome" 500.0 375.0)
      (minSizeRule "dev.zed.Zed" 360.0 240.0)
      (minSizeRule "com.apple.Safari" 574.0 220.0)
      (minSizeRule "app.zen-browser.zen" 500.0 495.0)
      (minSizeRule "org.mozilla.firefox" 500.0 120.0)
      (minSizeRule "company.thebrowser.dia" 500.0 420.0)
      (minSizeRule "com.spotify.client" 800.0 600.0)
      (minSizeRule "com.hnc.Discord" 800.0 500.0)
      (minSizeRule "com.mitchellh.ghostty" 90.0 48.0)
      (minSizeRule "com.microsoft.Outlook" 930.0 650.0)
      (minSizeRule "com.apple.MobileSMS" 660.0 320.0)
    ];

    monitorBarOverrides = [ ];
    monitorOrientationOverrides = [ ];
    monitorNiriOverrides = [ ];
    monitorDwindleOverrides = [ ];
    monitorGapOverrides = [ ];
  };
in
{
  config = lib.mkIf (userApps.omniwm.enable or false) {
    assertions = [
      {
        assertion = unknownBinds == [ ];
        message = "omniwm: niriFlow binds unknown action ids: ${toString unknownBinds}";
      }
      {
        assertion = duplicateIds == [ ];
        message = "omniwm: hotkeyIds has duplicates: ${toString duplicateIds}";
      }
      {
        assertion =
          let
            bound = lib.attrValues niriFlow;
          in
          lib.length bound == lib.length (lib.unique bound);
        message = "omniwm: two actions in niriFlow share one key chord";
      }
    ];

    programs.omniwm = {
      enable = true;
      inherit settings;
    };
  };
}
