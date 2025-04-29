#!/usr/bin/env bash

LIGHT_IMG="${1:?"Light image path is required"}"
DARK_IMG="${2:?"Dark image path is required"}"
OUTPUT="dynamic.heic"

# Check that input files exist
if [[ ! -f "$LIGHT_IMG" || ! -f "$DARK_IMG" ]]; then
    echo "❌ Missing input files: make sure light.jpg and dark.jpg are present."
    exit 1
fi

# Convert to TIFF with embedded tags
sips -s format tiff "$LIGHT_IMG" --out light.tiff
sips -s format tiff "$DARK_IMG" --out dark.tiff

# Combine into a single multi-page TIFF
tiffutil -cat light.tiff dark.tiff -out combined.tiff

# Convert to HEIC using built-in tool
heif-enc combined.tiff -o "$OUTPUT"

# Clean up
rm light.tiff dark.tiff combined.tiff

echo "✅ Dynamic wallpaper created: $OUTPUT"
