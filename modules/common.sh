#!/bin/bash
#
# Common functions for monitoring installation
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

handle_error() {
    log_error "$1"
    exit 1
}

cleanup() {
    if [[ -d "${TEMP_DIR:-}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
    log_info "Cleanup completed"
}

trap cleanup EXIT

create_temp_dir() {
    TEMP_DIR=$(mktemp -d)
    log_info "Created temporary directory: ${TEMP_DIR}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        handle_error "This script must be run as root"
    fi
}

check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        handle_error "This script is designed for Ubuntu systems only"
    fi

    UBUNTU_VERSION=$(grep -oP 'VERSION_ID="\K[^"]+' /etc/os-release)
    log_info "Detected Ubuntu version: ${UBUNTU_VERSION}"

    if [[ "${UBUNTU_VERSION}" != "20.04" && "${UBUNTU_VERSION}" != "22.04" ]]; then
        log_warning "This script is tested on Ubuntu 20.04 and 22.04. Your version may not be fully supported."
    fi
}

check_disk_space() {
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

create_user() {
    local username=$1

    if id "${username}" &>/dev/null; then
        log_info "User ${username} already exists"
        return 0
    fi

    log_info "Creating user: ${username}"
    useradd --no-create-home --shell /bin/false "${username}" || handle_error "Failed to create user: ${username}"
    log_success "User created: ${username}"
}

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

    local status
    status=$(systemctl is-active "${service_name}" 2>/dev/null)

    if [[ "${status}" == "active" ]]; then
        log_success "Service is running: ${service_name}"
    else
        handle_error "Service is not running: ${service_name} (Status: ${status})"
    fi
}

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

    mkdir -p "${extract_dir}"

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

backup_config_file() {
    local config_file=$1
    local backup_file="${config_file}.bak.$(date +%Y%m%d%H%M%S)"

    if [[ -f "${config_file}" ]]; then
        log_info "Backing up config file: ${config_file}"
        cp "${config_file}" "${backup_file}" || handle_error "Failed to backup config file: ${config_file}"
        log_success "Config file backed up: ${backup_file}"
    else
        log_info "No existing config file to backup: ${config_file}"
    fi
}


PROMETHEUS_CONF_DIR="/etc/prometheus"
PROMETHEUS_USER="prometheus"
PROMETHEUS_GROUP="prometheus"


reload_prometheus_config() {
    if systemctl list-units --full -all | grep -q 'prometheus.service'; then
        if systemctl is-active --quiet prometheus; then
            log_info "Reloading Prometheus configuration..."
            systemctl reload prometheus || handle_error "Failed to reload Prometheus service. Check config with 'promtool check config /etc/prometheus/prometheus.yml' and logs with 'journalctl -u prometheus'."
            log_success "Prometheus configuration reloaded."
        else
            log_warning "Prometheus service is installed but not active. Skipping reload."
        fi
    else
        log_info "Prometheus service not found. Skipping reload."
    fi
}

add_prometheus_scrape_config() {
    local job_name=$1
    local target=$2
    local config_file="/etc/prometheus/prometheus.yml"

    log_info "Attempting to add Prometheus scrape config for job '${job_name}' to ${config_file}"

    # Ensure the config file exists
    if [[ ! -f "${config_file}" ]]; then
        log_error "Prometheus configuration file ${config_file} not found. Cannot add scrape config."
        # Return non-zero, let the caller handle if it's fatal
        return 1
    fi

    # Ensure scrape_configs key exists (should always be true after base config creation)
    if ! grep -q "^scrape_configs:" "${config_file}"; then
        log_warning "scrape_configs key not found in ${config_file}. Adding it."
        # Append with a newline just in case the file doesn't end with one
        echo -e "\nscrape_configs:" >> "${config_file}" || { log_error "Failed to add scrape_configs key to ${config_file}"; return 1; }
    fi

    # Check if job already exists (simple grep check for the job_name line)
    # This assumes job names are unique and avoids complex YAML parsing in shell
    if grep -Eq "^\s*-\s*job_name:\s*'${job_name}'" "${config_file}"; then
        log_info "Job '${job_name}' already exists in ${config_file}. Skipping."
        return 0
    fi

    log_info "Adding scrape config for job '${job_name}'"

    # Append the new job configuration using cat << EOF to preserve formatting
    # Ensure a newline before the appended block in case the file doesn't end with one
    cat >> "${config_file}" << EOF

  - job_name: '${job_name}'
    static_configs:
      - targets: ['${target}']
EOF

    if [[ $? -ne 0 ]]; then
        log_error "Failed to append scrape config for job '${job_name}' to ${config_file}"
        return 1
    fi

    log_success "Successfully added scrape config for job '${job_name}' to ${config_file}"

    # Reload Prometheus config using the existing function
    reload_prometheus_config
    # Return the exit code of the reload command
    return $?
}

version_gt() {
    test "$(printf '%s\n' "$1" "$2" | sort -V | head -n 1)" != "$1"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}
check_dependencies() {
    log_info "Checking for required dependencies..."
    local missing_deps=()
    local base_dependencies=(
        wget
        tar
        unzip
        systemctl
        useradd
        groupadd
        git
        awk
        grep
        sed
        mktemp
        df
        ping
    )
    local dependencies=("${base_dependencies[@]}")

    if [[ "${INSTALL_PM2_EXPORTER:-false}" == "true" && -z "${PM2_USER_ARG:-}" ]]; then
         log_info "PM2 Exporter selected for global install, checking for npm and pm2..."
         dependencies+=(npm pm2)
    elif [[ "${INSTALL_PM2_EXPORTER:-false}" == "true" && -n "${PM2_USER_ARG:-}" ]]; then
         log_info "PM2 Exporter selected for user '${PM2_USER_ARG}', skipping global npm/pm2 check."
    fi


    for dep in "${dependencies[@]}"; do
        if ! command_exists "${dep}"; then
            missing_deps+=("${dep}")
        fi
    done

    if [[ ${#missing_deps[@]} -ne 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        handle_error "Please install the missing dependencies and try again."
    else
        log_success "All required dependencies are installed."
    fi
}


init_script() {
    log_info "Initializing installation script"
    create_temp_dir
    check_system
    check_dependencies
    detect_architecture
    update_package_lists
    log_success "Initialization complete"
}