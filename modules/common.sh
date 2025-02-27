#!/bin/bash
#
# Common functions for monitoring installation
#

# Set strict mode
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# System architecture detection
detect_architecture() {
    local arch
    arch=$(uname -m)

    case $arch in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="armv7"
            ;;
        armv6l)
            ARCH="armv6"
            ;;
        *)
            log_warning "Unsupported architecture: $arch"
            log_warning "Defaulting to amd64, but this may cause compatibility issues"
            ARCH="amd64"
            ;;
    esac

    log_info "Detected system architecture: $arch (using $ARCH for downloads)"
    export ARCH
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Error handling
handle_error() {
    log_error "$1"
    exit 1
}

# Trap for cleanup on exit
cleanup() {
    # Remove temporary files and directories
    if [[ -d "${TEMP_DIR:-}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi

    # Additional cleanup as needed
    log_info "Cleanup completed"
}

# Set trap for cleanup
trap cleanup EXIT

# Create temporary directory
create_temp_dir() {
    TEMP_DIR=$(mktemp -d)
    log_info "Created temporary directory: ${TEMP_DIR}"
}

# System checks
check_root() {
    if [[ $EUID -ne 0 ]]; then
        handle_error "This script must be run as root"
    fi
}

check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        handle_error "This script is designed for Ubuntu systems only"
    fi

    # Get Ubuntu version
    UBUNTU_VERSION=$(grep -oP 'VERSION_ID="\K[^"]+' /etc/os-release)
    log_info "Detected Ubuntu version: ${UBUNTU_VERSION}"

    # Check if version is supported
    if [[ "${UBUNTU_VERSION}" != "20.04" && "${UBUNTU_VERSION}" != "22.04" ]]; then
        log_warning "This script is tested on Ubuntu 20.04 and 22.04. Your version may not be fully supported."
    fi
}

check_disk_space() {
    # Check if there's at least 1GB of free space
    FREE_SPACE=$(df -m / | awk 'NR==2 {print $4}')
    if [[ ${FREE_SPACE} -lt 1024 ]]; then
        handle_error "Not enough disk space. At least 1GB of free space is required."
    fi
    log_info "Disk space check passed: ${FREE_SPACE}MB available"
}

check_internet_connection() {
    if ! ping -c 1 google.com &> /dev/null; then
        handle_error "Internet connection is required for installation"
    fi
    log_info "Internet connection check passed"
}

check_system() {
    log_info "Performing system checks..."
    check_root
    check_ubuntu
    check_disk_space
    check_internet_connection
    log_success "All system checks passed"
}

# Package management wrappers
update_package_lists() {
    log_info "Updating package lists..."
    apt-get update -qq || handle_error "Failed to update package lists"
    log_success "Package lists updated"
}

install_package() {
    local package=$1
    log_info "Installing package: ${package}"
    apt-get install -y "${package}" || handle_error "Failed to install package: ${package}"
    log_success "Package installed: ${package}"
}

install_packages() {
    log_info "Installing packages: $*"
    apt-get install -y "$@" || handle_error "Failed to install packages: $*"
    log_success "Packages installed: $*"
}

# User creation utilities
create_user() {
    local username=$1

    # Check if user already exists
    if id "${username}" &>/dev/null; then
        log_info "User ${username} already exists"
        return 0
    fi

    log_info "Creating user: ${username}"
    useradd --no-create-home --shell /bin/false "${username}" || handle_error "Failed to create user: ${username}"
    log_success "User created: ${username}"
}

# Directory management
create_directory() {
    local dir=$1
    local owner=${2:-root}
    local group=${3:-root}
    local mode=${4:-0755}

    log_info "Creating directory: ${dir}"
    mkdir -p "${dir}" || handle_error "Failed to create directory: ${dir}"
    chown "${owner}:${group}" "${dir}" || handle_error "Failed to set ownership on directory: ${dir}"
    chmod "${mode}" "${dir}" || handle_error "Failed to set permissions on directory: ${dir}"
    log_success "Directory created: ${dir}"
}

# Service management
create_systemd_service() {
    local service_name=$1
    local service_content=$2
    local service_file="/etc/systemd/system/${service_name}.service"

    log_info "Creating systemd service: ${service_name}"
    echo "${service_content}" > "${service_file}" || handle_error "Failed to create service file: ${service_file}"
    chmod 644 "${service_file}" || handle_error "Failed to set permissions on service file: ${service_file}"
    log_success "Systemd service created: ${service_name}"
}

reload_systemd() {
    log_info "Reloading systemd"
    systemctl daemon-reload || handle_error "Failed to reload systemd"
    log_success "Systemd reloaded"
}

enable_service() {
    local service_name=$1

    log_info "Enabling service: ${service_name}"
    systemctl enable "${service_name}" || handle_error "Failed to enable service: ${service_name}"
    log_success "Service enabled: ${service_name}"
}

start_service() {
    local service_name=$1

    log_info "Starting service: ${service_name}"
    systemctl start "${service_name}" || handle_error "Failed to start service: ${service_name}"
    log_success "Service started: ${service_name}"
}

restart_service() {
    local service_name=$1

    log_info "Restarting service: ${service_name}"
    systemctl restart "${service_name}" || handle_error "Failed to restart service: ${service_name}"
    log_success "Service restarted: ${service_name}"
}

check_service_status() {
    local service_name=$1

    log_info "Checking service status: ${service_name}"

    # Check if service is active using systemctl is-active
    local status
    status=$(systemctl is-active "${service_name}" 2>/dev/null)

    if [[ "${status}" == "active" ]]; then
        log_success "Service is running: ${service_name}"
    else
        handle_error "Service is not running: ${service_name} (Status: ${status})"
    fi
}

# Download utilities
download_file() {
    local url=$1
    local output_file=$2

    log_info "Downloading file: ${url}"
    wget -q "${url}" -O "${output_file}" || handle_error "Failed to download file: ${url}"
    log_success "File downloaded: ${output_file}"
}

extract_archive() {
    local archive_file=$1
    local extract_dir=$2

    log_info "Extracting archive: ${archive_file}"

    # Create extraction directory if it doesn't exist
    mkdir -p "${extract_dir}"

    # Extract based on file extension
    if [[ "${archive_file}" == *.tar.gz || "${archive_file}" == *.tgz ]]; then
        tar -xzf "${archive_file}" -C "${extract_dir}" || handle_error "Failed to extract archive: ${archive_file}"
    elif [[ "${archive_file}" == *.tar.bz2 ]]; then
        tar -xjf "${archive_file}" -C "${extract_dir}" || handle_error "Failed to extract archive: ${archive_file}"
    elif [[ "${archive_file}" == *.zip ]]; then
        unzip -q "${archive_file}" -d "${extract_dir}" || handle_error "Failed to extract archive: ${archive_file}"
    else
        handle_error "Unsupported archive format: ${archive_file}"
    fi

    log_success "Archive extracted: ${archive_file}"
}

# Configuration file utilities
backup_config_file() {
    local config_file=$1
    local backup_file="${config_file}.bak.$(date +%Y%m%d%H%M%S)"

    # Only backup if file exists
    if [[ -f "${config_file}" ]]; then
        log_info "Backing up config file: ${config_file}"
        cp "${config_file}" "${backup_file}" || handle_error "Failed to backup config file: ${config_file}"
        log_success "Config file backed up: ${backup_file}"
    else
        log_info "No existing config file to backup: ${config_file}"
    fi
}

# YAML manipulation functions
add_yaml_block() {
    local file=$1
    local block=$2
    local section=$3

    # Backup the file
    backup_config_file "${file}"

    # Check if section exists
    if grep -q "${section}:" "${file}"; then
        # Add block to existing section
        # Use a more reliable approach to insert the block after the section
        awk -v section="${section}:" -v block="${block}" '
        $0 ~ section {
            print $0;
            print block;
            next;
        }
        { print $0 }
        ' "${file}" > "${file}.tmp" && mv "${file}.tmp" "${file}" || handle_error "Failed to add YAML block to ${file}"
    else
        # Add new section with block
        echo -e "\n${section}:\n${block}" >> "${file}" || handle_error "Failed to add YAML section to ${file}"
    fi

    log_success "YAML block added to ${file}"
}

# Version comparison utility
version_gt() {
    test "$(printf '%s\n' "$1" "$2" | sort -V | head -n 1)" != "$1"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Initialize the script
init_script() {
    log_info "Initializing installation script"
    create_temp_dir
    check_system
    detect_architecture
    update_package_lists
    log_success "Initialization complete"
}