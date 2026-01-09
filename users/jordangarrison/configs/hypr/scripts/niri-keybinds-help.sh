#!/usr/bin/env bash
# Niri Keybinds Help - Display all Niri keybindings
# Since niri doesn't expose bindings via IPC like Hyprland, this is a curated list
# Trigger with: Super + /

show_keybinds() {
  cat << 'EOF'
[LAUNCHERS]
Super + Return            → Terminal (WezTerm)
Super + B                 → Browser (Brave)
Super + E                 → Emacs
Super + N                 → Obsidian
Super + F                 → File manager (Yazi)
Super + Shift + F         → File manager (Nautilus)
Super + Space             → App launcher (Noctalia)
Super + Semicolon         → Emoji picker (rofimoji)

[WINDOW CONTROLS]
Super + Q                 → Close window
Super + V                 → Toggle floating
Super + M                 → Maximize column
Super + Shift + M         → Fullscreen window
Super + R                 → Cycle column widths
Super + T                 → Toggle tabbed display
Super + G                 → Center column

[FOCUS (vim-style)]
Super + H                 → Focus column left
Super + L                 → Focus column right
Super + J                 → Focus window down
Super + K                 → Focus window up
Super + Tab               → Toggle overview

[MOVE WINDOWS]
Super + Shift + H         → Move column left
Super + Shift + L         → Move column right
Super + Shift + J         → Move window down
Super + Shift + K         → Move window up

[COLUMN MANAGEMENT]
Super + Ctrl + H          → Consume window into column
Super + Ctrl + L          → Expel window from column
Super + Minus             → Shrink column width 10%
Super + Equal             → Grow column width 10%
Super + Shift + Minus     → Shrink window height 10%
Super + Shift + Equal     → Grow window height 10%

[WORKSPACES]
Super + 1-0               → Focus workspace 1-10
Super + Shift + 1-0       → Move window to workspace
Super + Page Down         → Focus workspace down
Super + Page Up           → Focus workspace up
Super + Shift + Page Down → Move window to workspace down
Super + Shift + Page Up   → Move window to workspace up

[MONITORS]
Super + Comma             → Focus monitor left
Super + Period            → Focus monitor right
Super + Shift + Comma     → Move window to monitor left
Super + Shift + Period    → Move window to monitor right

[SCREENSHOTS]
Print                     → Screenshot (niri built-in)
Shift + Print             → Screenshot window
Super + Alt + S           → Region + Satty annotation
Super + Alt + A           → Full screen + Satty
Super + Alt + C           → Region to clipboard
Super + Alt + F           → Full screen to clipboard

[SYSTEM]
Super + C                 → Clipboard history
Super + Ctrl + Alt + L    → Lock screen
Super + Shift + C         → Reload niri config
Super + Shift + Q         → Quit niri
Super + Shift + /         → Show niri hotkey overlay
Super + /                 → Show this keybindings help

[MEDIA KEYS]
XF86AudioRaiseVolume      → Volume up
XF86AudioLowerVolume      → Volume down
XF86AudioMute             → Toggle mute
XF86MonBrightnessUp       → Brightness up
XF86MonBrightnessDown     → Brightness down
XF86AudioPlay             → Play/pause media
XF86AudioNext             → Next track
XF86AudioPrev             → Previous track
EOF
}

# Check what's available for display
if command -v rofi &> /dev/null; then
  show_keybinds | rofi -dmenu -p "Niri Keybindings" -i -markup-rows -theme-str 'window {width: 60%;}'
elif command -v walker &> /dev/null; then
  show_keybinds | walker --dmenu -p "Niri Keybindings"
else
  # Fallback to terminal with less
  show_keybinds | less
fi
