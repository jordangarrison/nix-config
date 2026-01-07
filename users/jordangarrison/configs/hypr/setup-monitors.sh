#!/usr/bin/env bash
# Monitor Setup Script for Hyprland
# Symlinks the appropriate monitor config based on hostname

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORS_DIR="${SCRIPT_DIR}/monitors"
CONFIG_DIR="${HOME}/.config/hypr"
TARGET="${CONFIG_DIR}/monitors.conf"

# Get hostname
HOSTNAME=$(hostname)

echo "Setting up monitors for: ${HOSTNAME}"

# Ensure config directory exists
mkdir -p "${CONFIG_DIR}"

# Check if monitor config exists for this host
if [[ -f "${MONITORS_DIR}/${HOSTNAME}.conf" ]]; then
    echo "Found monitor config: ${MONITORS_DIR}/${HOSTNAME}.conf"

    # Remove existing symlink or file
    if [[ -L "${TARGET}" ]] || [[ -f "${TARGET}" ]]; then
        rm "${TARGET}"
        echo "Removed existing monitors.conf"
    fi

    # Create symlink
    ln -s "${MONITORS_DIR}/${HOSTNAME}.conf" "${TARGET}"
    echo "Created symlink: ${TARGET} -> ${MONITORS_DIR}/${HOSTNAME}.conf"

    echo ""
    echo "Monitor configuration applied!"
    echo "Reload Hyprland with: hyprctl reload"
else
    echo "Warning: No monitor config found for '${HOSTNAME}'"
    echo ""
    echo "Available configurations:"
    ls -1 "${MONITORS_DIR}/"*.conf 2>/dev/null || echo "  (none found)"
    echo ""
    echo "Creating default monitor config..."

    # Create a default config
    cat > "${TARGET}" << 'EOF'
# Default Monitor Configuration
# Edit this file or create a host-specific config in monitors/

# Auto-detect and configure monitors
monitor = , preferred, auto, 1

# Default workspace distribution
workspace = 1, default:true
workspace = 2
workspace = 3
workspace = 4
workspace = 5
workspace = 6
workspace = 7
workspace = 8
workspace = 9
workspace = 10
EOF

    echo "Created default config at: ${TARGET}"
    echo ""
    echo "To create a host-specific config:"
    echo "  1. Create ${MONITORS_DIR}/${HOSTNAME}.conf"
    echo "  2. Run this script again"
fi

echo ""
echo "Done!"
