#!/bin/bash

# Get absolute path to script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source installation modules
source "${SCRIPT_DIR}/lib/install_grafana.sh"
source "${SCRIPT_DIR}/lib/install_prometheus.sh"
source "${SCRIPT_DIR}/lib/install_node_exporter.sh"
source "${SCRIPT_DIR}/lib/install_mysql_exporter.sh"
source "${SCRIPT_DIR}/lib/install_blackbox_exporter.sh"
source "${SCRIPT_DIR}/lib/install_pm2_exporter.sh"
source "${SCRIPT_DIR}/lib/install_duplicati_exporter.sh"

# Monitoring Stack Installation Script
# Version: 1.0.0
# Description: Installs and configures Grafana, Prometheus, and various exporters
# Supports: Ubuntu and CentOS distributions

set -euo pipefail

# Constants
GRAFANA_VERSION="10.4.2"
PROMETHEUS_VERSION="3.1.0"
NODE_EXPORTER_VERSION="1.8.2"
MYSQL_EXPORTER_VERSION="0.16.0"
BLACKBOX_EXPORTER_VERSION="0.25.0"

# Service users
GRAFANA_USER="grafana"
PROMETHEUS_USER="prometheus"
NODE_EXPORTER_USER="node_exporter"
MYSQL_EXPORTER_USER="mysql_exporter"
BLACKBOX_EXPORTER_USER="blackbox_exporter"
PM2_EXPORTER_USER="pm2_exporter"
DUPLICATI_EXPORTER_USER="duplicati_exporter"

# Log file
LOG_FILE="/var/log/monitoring-setup.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper Functions
get_value() {
    local var_name=$1
    local prompt_text=$2
    local default_value=$3
    local current_value

    # Use eval to safely get the current value
    eval "current_value=\${$var_name:-}"

    if [ -z "$current_value" ]; then
        read -p "$prompt_text [$default_value]: " value
        value=${value:-$default_value}
        eval "$var_name='$value'"
        echo "$value"
    else
        echo "$current_value"
    fi
}

validate_domains() {
    local domains=${1//,/ }
    for domain in $domains; do
        if [[ $domain == "localhost" ]]; then
            continue
        fi
        if ! [[ $domain =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
            log_error "Invalid domain format: $domain"
            return 1
        fi
    done
    return 0
}

validate_pm2_user() {
    local user=$1

    # Check if user exists
    if ! id "$user" >/dev/null 2>&1; then
        log_error "User $user does not exist"
        return 1
    fi

    return 0
}

generate_random_password() {
    openssl rand -base64 12 | tr -d '/+='
}

# Logging functions
log() {
    echo -e "${TIMESTAMP} - $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}${TIMESTAMP} - ✓ $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}${TIMESTAMP} - ✗ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}${TIMESTAMP} - ⚠ $1${NC}" | tee -a "$LOG_FILE"
}

# Error handler
handle_error() {
    log_error "An error occurred on line $1"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Detect OS and version
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VERSION=$VERSION_ID
        log "Detected OS: $OS $VERSION"
    else
        log_error "Cannot detect OS"
        exit 1
    fi
}

# Check system dependencies
check_dependencies() {
    local deps=("curl" "wget" "systemctl")
    local missing_deps=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi

    log_success "All dependencies are satisfied"
}

# Create service user if it doesn't exist
create_service_user() {
    local username=$1
    local home_opt=$2

    if ! id "$username" >/dev/null 2>&1; then
        if [ "$home_opt" = "--no-home" ]; then
            useradd --system --no-create-home --shell /sbin/nologin "$username"
        else
            useradd --system --no-create-home --home-dir "$home_opt" --shell /sbin/nologin "$username"
        fi
        log_success "Created service user: $username"
    else
        log "Service user $username already exists"
    fi
}

# Install required packages based on OS
install_required_packages() {
    case $OS in
        "Ubuntu")
            apt-get update
            apt-get install -y apt-transport-https software-properties-common wget
            ;;
        "CentOS Linux")
            yum install -y epel-release wget
            ;;
        *)
            log_error "Unsupported operating system: $OS"
            exit 1
            ;;
    esac
    log_success "Installed required packages"
}

# Environment setup
setup_environment() {
    log "Setting up environment variables"

    # Blackbox Exporter targets
    BLACKBOX_TARGETS=$(get_value "BLACKBOX_TARGETS" \
        "Enter comma-separated list of domains to monitor" \
        "localhost")

    if ! validate_domains "$BLACKBOX_TARGETS"; then
        exit 1
    fi
    log_success "Blackbox targets configured: $BLACKBOX_TARGETS"

    # MySQL Exporter password
    MYSQL_EXPORTER_PASSWORD=$(get_value "MYSQL_EXPORTER_PASSWORD" \
        "Enter password for MySQL exporter user (leave empty for random)" \
        "$(generate_random_password)")
    log_success "MySQL exporter password configured"

    # PM2 user
    PM2_USER=$(get_value "PM2_USER" \
        "Enter username of the PM2 service user" \
        "$(whoami)")

    if ! validate_pm2_user "$PM2_USER"; then
        exit 1
    fi
    log_success "PM2 user configured: $PM2_USER"

    # Optional Mattermost webhook
    read -p "Would you like to configure Mattermost alerts? (y/N): " configure_mattermost
    if [[ $configure_mattermost =~ ^[Yy]$ ]]; then
        MATTERMOST_WEBHOOK_URL=$(get_value "MATTERMOST_WEBHOOK_URL" \
            "Enter Mattermost webhook URL" \
            "")
        if [ -n "$MATTERMOST_WEBHOOK_URL" ]; then
            log_success "Mattermost webhook configured"
        else
            log_warning "Mattermost webhook skipped"
        fi
    else
        MATTERMOST_WEBHOOK_URL=""
        log "Mattermost alerts not configured"
    fi
}

# Main installation function
main() {
    log "Starting monitoring stack installation"

    # Setup environment variables
    setup_environment

    # Initial checks
    check_root
    detect_os
    check_dependencies
    install_required_packages

    # Create service users
    create_service_user "$GRAFANA_USER" "/usr/share/grafana"  # Grafana needs a home directory for plugins
    create_service_user "$PROMETHEUS_USER" --no-home
    create_service_user "$NODE_EXPORTER_USER" --no-home
    create_service_user "$MYSQL_EXPORTER_USER" --no-home
    create_service_user "$BLACKBOX_EXPORTER_USER" --no-home
    create_service_user "$DUPLICATI_EXPORTER_USER" --no-home

    log_success "Initial setup completed"

    # Install and configure Grafana
    install_grafana

    # Install and configure Prometheus
    install_prometheus_stack

    # Install and configure Node Exporter
    install_node_exporter_stack

    # Install and configure MySQL Exporter
    install_mysql_exporter_stack

    # Install and configure Blackbox Exporter
    install_blackbox_exporter_stack

    # Install and configure PM2 Exporter
    install_pm2_exporter_stack

    # Install and configure Duplicati Exporter
    install_duplicati_exporter_stack

    # Copy dashboard templates
    copy_dashboard_templates
}

# Copy dashboard templates to Grafana
copy_dashboard_templates() {
    log "Copying dashboard templates"

    local dashboard_dir="/etc/grafana/dashboards"
    local notifiers_dir="/etc/grafana/provisioning/notifiers"
    local source_dir="${SCRIPT_DIR}/config/grafana/provisioning"

    # Create required directories
    mkdir -p "$dashboard_dir"
    mkdir -p "$notifiers_dir"

    # Copy dashboard files and notifiers
    if [ -d "$source_dir/dashboards" ]; then
        cp -r "$source_dir/dashboards"/*.json "$dashboard_dir/" 2>/dev/null || true
    fi

    if [ -d "$source_dir/notifiers" ]; then
        cp -r "$source_dir/notifiers"/* "$notifiers_dir/" 2>/dev/null || true
    fi

    # Set correct ownership
    chown -R "${GRAFANA_USER}:${GRAFANA_USER}" "$dashboard_dir"
    chown -R "${GRAFANA_USER}:${GRAFANA_USER}" "$notifiers_dir"

    log_success "Dashboard templates copied successfully"
}

# Execute main function
main "$@"
