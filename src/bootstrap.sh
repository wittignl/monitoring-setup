#!/bin/bash

set -euo pipefail

# Constants
REPO_URL="https://github.com/user/repo/raw/main"
TEMP_DIR="/tmp/monitoring-setup-$$"
CHECKSUM_URL="${REPO_URL}/checksums.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "$1"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

log_error() {
    echo -e "${RED}✗ $1${NC}"
}

