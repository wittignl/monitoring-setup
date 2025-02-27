#!/bin/bash
#
# Monitoring Stack Installation Script
# Installs Prometheus, Grafana, and various exporters on Ubuntu
#
# Usage: ./install.sh [options]
# Options:
#   --help                  Display this help message
#   --prometheus            Install Prometheus
#   --grafana               Install Grafana
#   --node-exporter         Install Node Exporter
#   --blackbox-exporter     Install Blackbox Exporter
#   --mysql-exporter        Install MySQL Exporter
#   --pm2-exporter          Install PM2 Exporter
#   --all                   Install all components
#   --skip-provisioning     Skip Grafana provisioning
#   --version VERSION       Specify version for components
#   --pm2-user USER         Specify PM2 user (defaults to current user)
#
# Example: ./install.sh --all
#          ./install.sh --prometheus --grafana --node-exporter
#

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo ".")"
MODULE_DIR="${SCRIPT_DIR}/modules"
PROVISIONING_DIR="${SCRIPT_DIR}/provisioning"

# GitHub repository information
REPO_OWNER="brentdenboer"
REPO_NAME="monitoring-setup"
BRANCH="main"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"

# Create modules directory if it doesn't exist
mkdir -p "${MODULE_DIR}"

# Function to download a module file if it doesn't exist locally
download_module() {
    local module_name=$1
    local module_path="${MODULE_DIR}/${module_name}"

    if [[ ! -f "${module_path}" ]]; then
        echo "Downloading module: ${module_name}"
        curl -s -o "${module_path}" "${GITHUB_RAW_URL}/modules/${module_name}"
        chmod +x "${module_path}"
    fi
}

# Download all required module files
download_module "common.sh"
download_module "prometheus.sh"
download_module "grafana.sh"
download_module "node_exporter.sh"
download_module "blackbox_exporter.sh"
download_module "mysql_exporter.sh"
download_module "pm2_exporter.sh"

# Create provisioning directory structure if it doesn't exist
mkdir -p "${PROVISIONING_DIR}/alerting"
mkdir -p "${PROVISIONING_DIR}/dashboards"
mkdir -p "${PROVISIONING_DIR}/datasources"

# Download provisioning files if they don't exist
download_provisioning_file() {
    local file_path=$1
    local local_path="${PROVISIONING_DIR}/${file_path}"
    local dir_path=$(dirname "${local_path}")

    mkdir -p "${dir_path}"

    if [[ ! -f "${local_path}" ]]; then
        echo "Downloading provisioning file: ${file_path}"
        curl -s -o "${local_path}" "${GITHUB_RAW_URL}/provisioning/${file_path}"
    fi
}

# Download essential provisioning files
download_provisioning_file "datasources/prometheus.yml"
download_provisioning_file "dashboards/default.yml"

# Source modules
source "${MODULE_DIR}/common.sh"
source "${MODULE_DIR}/prometheus.sh"
source "${MODULE_DIR}/grafana.sh"
source "${MODULE_DIR}/node_exporter.sh"
source "${MODULE_DIR}/blackbox_exporter.sh"
source "${MODULE_DIR}/mysql_exporter.sh"
source "${MODULE_DIR}/pm2_exporter.sh"

# Default options
INSTALL_PROMETHEUS=false
INSTALL_GRAFANA=false
INSTALL_NODE_EXPORTER=false
INSTALL_BLACKBOX_EXPORTER=false
INSTALL_MYSQL_EXPORTER=false
INSTALL_PM2_EXPORTER=false
SKIP_PROVISIONING=false
COMPONENT_VERSION=""
PM2_USER_VALUE=""

# Display help message
display_help() {
    cat << EOF
Monitoring Stack Installation Script

Usage: ./install.sh [options]

Options:
  --help                  Display this help message
  --prometheus            Install Prometheus
  --grafana               Install Grafana
  --node-exporter         Install Node Exporter
  --blackbox-exporter     Install Blackbox Exporter
  --mysql-exporter        Install MySQL Exporter
  --pm2-exporter          Install PM2 Exporter
  --all                   Install all components
  --skip-provisioning     Skip Grafana provisioning
  --version VERSION       Specify version for components
  --pm2-user USER         Specify PM2 user (defaults to current user)

Example: ./install.sh --all
         ./install.sh --prometheus --grafana --node-exporter
         ./install.sh --pm2-exporter --pm2-user nodejs
EOF
}

# Parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help)
                display_help
                exit 0
                ;;
            --prometheus)
                INSTALL_PROMETHEUS=true
                shift
                ;;
            --grafana)
                INSTALL_GRAFANA=true
                shift
                ;;
            --node-exporter)
                INSTALL_NODE_EXPORTER=true
                shift
                ;;
            --blackbox-exporter)
                INSTALL_BLACKBOX_EXPORTER=true
                shift
                ;;
            --mysql-exporter)
                INSTALL_MYSQL_EXPORTER=true
                shift
                ;;
            --pm2-exporter)
                INSTALL_PM2_EXPORTER=true
                shift
                ;;
            --all)
                INSTALL_PROMETHEUS=true
                INSTALL_GRAFANA=true
                INSTALL_NODE_EXPORTER=true
                INSTALL_BLACKBOX_EXPORTER=true
                INSTALL_MYSQL_EXPORTER=true
                INSTALL_PM2_EXPORTER=true
                shift
                ;;
            --skip-provisioning)
                SKIP_PROVISIONING=true
                shift
                ;;
            --version)
                COMPONENT_VERSION="$2"
                shift 2
                ;;
            --pm2-user)
                PM2_USER_VALUE="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                display_help
                exit 1
                ;;
        esac
    done

    # If no components selected, display help
    if [[ "${INSTALL_PROMETHEUS}" == "false" && \
          "${INSTALL_GRAFANA}" == "false" && \
          "${INSTALL_NODE_EXPORTER}" == "false" && \
          "${INSTALL_BLACKBOX_EXPORTER}" == "false" && \
          "${INSTALL_MYSQL_EXPORTER}" == "false" && \
          "${INSTALL_PM2_EXPORTER}" == "false" ]]; then
        log_error "No components selected for installation"
        display_help
        exit 1
    fi
}

# Install selected components
install_components() {
    # Initialize script
    init_script

    # Install Prometheus
    if [[ "${INSTALL_PROMETHEUS}" == "true" ]]; then
        if [[ -n "${COMPONENT_VERSION}" ]]; then
            install_prometheus "${COMPONENT_VERSION}"
        else
            install_prometheus
        fi
    fi

    # Install Grafana
    if [[ "${INSTALL_GRAFANA}" == "true" ]]; then
        install_grafana

        # Provision Grafana if not skipped
        if [[ "${SKIP_PROVISIONING}" == "false" ]]; then
            provision_grafana "${PROVISIONING_DIR}"
        fi
    fi

    # Install Node Exporter
    if [[ "${INSTALL_NODE_EXPORTER}" == "true" ]]; then
        if [[ -n "${COMPONENT_VERSION}" ]]; then
            install_node_exporter "${COMPONENT_VERSION}"
        else
            install_node_exporter
        fi
    fi

    # Install Blackbox Exporter
    if [[ "${INSTALL_BLACKBOX_EXPORTER}" == "true" ]]; then
        if [[ -n "${COMPONENT_VERSION}" ]]; then
            install_blackbox_exporter "${COMPONENT_VERSION}"
        else
            install_blackbox_exporter
        fi
    fi

    # Install MySQL Exporter
    if [[ "${INSTALL_MYSQL_EXPORTER}" == "true" ]]; then
        if [[ -n "${COMPONENT_VERSION}" ]]; then
            install_mysql_exporter "${COMPONENT_VERSION}"
        else
            install_mysql_exporter
        fi
    fi

    # Install PM2 Exporter
    if [[ "${INSTALL_PM2_EXPORTER}" == "true" ]]; then
        install_pm2_exporter "${PM2_USER_VALUE}"
    fi
}

# Display final status
display_status() {
    log_info "Installation completed"

    # Check Prometheus status
    if [[ "${INSTALL_PROMETHEUS}" == "true" ]]; then
        check_prometheus
        log_info "Prometheus URL: http://localhost:${PROMETHEUS_PORT}"
    fi

    # Check Grafana status
    if [[ "${INSTALL_GRAFANA}" == "true" ]]; then
        check_grafana
        log_info "Grafana URL: http://localhost:${GRAFANA_PORT}"
        log_info "Default Grafana credentials: admin/admin"
    fi

    # Check Node Exporter status
    if [[ "${INSTALL_NODE_EXPORTER}" == "true" ]]; then
        check_node_exporter
    fi

    # Check Blackbox Exporter status
    if [[ "${INSTALL_BLACKBOX_EXPORTER}" == "true" ]]; then
        check_blackbox_exporter
    fi

    # Check MySQL Exporter status
    if [[ "${INSTALL_MYSQL_EXPORTER}" == "true" ]]; then
        check_mysql_exporter

        # Display MySQL exporter password if it was set
        if [[ -n "${MYSQL_EXPORTER_PASSWORD_USED}" ]]; then
            log_info "MySQL Exporter user: mysqld_exporter"
            log_info "MySQL Exporter password: ${MYSQL_EXPORTER_PASSWORD_USED}"
            log_info "MySQL Exporter config file: ${MYSQL_EXPORTER_CONFIG_FILE}"
        fi
    fi

    # Check PM2 Exporter status
    if [[ "${INSTALL_PM2_EXPORTER}" == "true" ]]; then
        check_pm2_exporter
    fi

    log_success "Monitoring stack installation completed successfully"
}

# Main function
main() {
    # Parse command-line arguments
    parse_arguments "$@"

    # Install selected components
    install_components

    # Display final status
    display_status
}

# Run main function
main "$@"