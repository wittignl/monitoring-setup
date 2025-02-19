#!/bin/bash

set -euo pipefail

# Create temporary directory
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Download and extract project files
echo "Downloading monitoring setup files..."
curl -sSL https://github.com/user/repo/archive/main.tar.gz | tar -xz -C "$TMP_DIR"

# Move to the extracted directory
cd "$TMP_DIR/repo-main"

# Execute main installation script
echo "Starting installation..."
bash src/main.sh

# Cleanup is handled by trap
