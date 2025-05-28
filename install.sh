#!/bin/bash
#
# Monitoring Stack Installation/Uninstallation Script
# Installs/Uninstalls Prometheus, Grafana, and various exporters on Ubuntu
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo ".")"
MODULE_DIR="${SCRIPT_DIR}/modules"
PROVISIONING_DIR="${SCRIPT_DIR}/provisioning"

REPO_OWNER="brentdenboer"
REPO_NAME="monitoring-setup"
BRANCH="main"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"


mkdir -p "${MODULE_DIR}"
mkdir -p "${PROVISIONING_DIR}/alerting"
mkdir -p "${PROVISIONING_DIR}/dashboards"
mkdir -p "${PROVISIONING_DIR}/datasources"

download_file_if_missing() {
    local remote_path=$1
    local local_path=$2
    local make_executable=${3:-false}

    if [[ ! -f "${local_path}" ]]; then
        local url="${GITHUB_RAW_URL}/${remote_path}"
        local dir_path=$(dirname "${local_path}")
        mkdir -p "${dir_path}"

        echo "Downloading: ${remote_path} -> ${local_path}"
        if curl -s -f -o "${local_path}" "${url}"; then
            echo "Download successful."
            if [[ "$make_executable" == "true" ]]; then
                chmod +x "${local_path}"
            fi
        else
            echo "ERROR: Failed to download ${url}. Please check network connection and URL." >&2
            if [[ "$remote_path" == modules/* ]]; then
                 exit 1
            fi
        fi
    fi
}

download_file_if_missing "modules/common.sh" "${MODULE_DIR}/common.sh" true
download_file_if_missing "modules/prometheus.sh" "${MODULE_DIR}/prometheus.sh" true
download_file_if_missing "modules/grafana.sh" "${MODULE_DIR}/grafana.sh" true
download_file_if_missing "modules/node_exporter.sh" "${MODULE_DIR}/node_exporter.sh" true
download_file_if_missing "modules/blackbox_exporter.sh" "${MODULE_DIR}/blackbox_exporter.sh" true
download_file_if_missing "modules/mysql_exporter.sh" "${MODULE_DIR}/mysql_exporter.sh" true
download_file_if_missing "modules/pm2_exporter.sh" "${MODULE_DIR}/pm2_exporter.sh" true

download_file_if_missing "provisioning/datasources/prometheus.yml" "${PROVISIONING_DIR}/datasources/prometheus.yml"
download_file_if_missing "provisioning/dashboards/default.yml" "${PROVISIONING_DIR}/dashboards/default.yml"

source "${MODULE_DIR}/common.sh" || { echo "ERROR: Failed to source common.sh" >&2; exit 1; }

source_module() {
    local module_file="${MODULE_DIR}/$1"
    if [[ -f "$module_file" ]]; then
        source "$module_file" || { log_error "Failed to source $1"; exit 1; }
    else
        log_error "Module file $1 not found."
        exit 1
    fi
}
source_module "prometheus.sh"
source_module "grafana.sh"
source_module "node_exporter.sh"
source_module "blackbox_exporter.sh"
source_module "mysql_exporter.sh"
source_module "pm2_exporter.sh"

ACTION="install"
INSTALL_PROMETHEUS=false
INSTALL_GRAFANA=false
INSTALL_NODE_EXPORTER=false
INSTALL_BLACKBOX_EXPORTER=false
INSTALL_MYSQL_EXPORTER=false
INSTALL_PM2_EXPORTER=false
SKIP_PROVISIONING=false
COMPONENT_VERSION=""
MYSQL_PASSWORD_ARG=""
GRAFANA_USER_ARG=""
GRAFANA_PASSWORD_ARG=""
GRAFANA_URL_ARG=""
PM2_USER_ARG=""


display_help() {
    cat << EOF
Monitoring Stack Installation/Uninstallation Script

Usage: ./install.sh [options]

Options:
  --help                  Display this help message
  --uninstall             Uninstall selected components instead of installing

  Installation/Uninstallation Targets:
  --prometheus            Select Prometheus
  --grafana               Select Grafana
  --node-exporter         Select Node Exporter
  --blackbox-exporter     Select Blackbox Exporter
  --mysql-exporter        Select MySQL Exporter
  --pm2-exporter          Select PM2 Exporter
  --all                   Select all components

  Installation Options:
  --skip-provisioning     Skip Grafana provisioning during installation
  --version VERSION       Specify version for components (applied to all selected)
  --mysql-password PWD    Password for MySQL Exporter config (required for install)
                          (Alternatively, set MYSQL_EXPORTER_PASSWORD env var)
  --grafana-user USER     Admin username for Grafana (defaults to 'admin')
                          (Alternatively, set GRAFANA_ADMIN_USER env var)
  --grafana-password PWD  Admin password for Grafana (required for install)
                          (Alternatively, set GRAFANA_ADMIN_PASSWORD env var)
  --grafana-url URL       External root URL for Grafana (e.g., https://grafana.example.com)
                          (Alternatively, set GRAFANA_ROOT_URL env var)

Examples:
  ./install.sh --all --mysql-password 'mysql_pass' --grafana-password 'graf_pass' --grafana-url 'http://my-server:3000'

  ./install.sh --prometheus --node-exporter

  ./install.sh --uninstall --grafana --prometheus

  export MYSQL_EXPORTER_PASSWORD='mysql_pass'
  export GRAFANA_ADMIN_PASSWORD='graf_pass'
  ./install.sh --all --grafana-url 'http://my-server:3000'

EOF
}

parse_arguments() {
    local short_opts=""
    local long_opts="help,uninstall,prometheus,grafana,node-exporter,blackbox-exporter,mysql-exporter,pm2-exporter,all,skip-provisioning,version:,mysql-password:,grafana-user:,grafana-password:,grafana-url:,pm2-user:"

    parsed_opts=$(getopt -o "$short_opts" --long "$long_opts" -n "$(basename "$0")" -- "$@")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to parse options."
        display_help
        exit 1
    fi

    eval set -- "$parsed_opts"

    while true; do
        case "$1" in
            --help) display_help; exit 0 ;;
            --uninstall) ACTION="uninstall"; shift ;;
            --prometheus) INSTALL_PROMETHEUS=true; shift ;;
            --grafana) INSTALL_GRAFANA=true; shift ;;
            --node-exporter) INSTALL_NODE_EXPORTER=true; shift ;;
            --blackbox-exporter) INSTALL_BLACKBOX_EXPORTER=true; shift ;;
            --mysql-exporter) INSTALL_MYSQL_EXPORTER=true; shift ;;
            --pm2-exporter) INSTALL_PM2_EXPORTER=true; shift ;;
            --all)
                INSTALL_PROMETHEUS=true; INSTALL_GRAFANA=true; INSTALL_NODE_EXPORTER=true;
                INSTALL_BLACKBOX_EXPORTER=true; INSTALL_MYSQL_EXPORTER=true; INSTALL_PM2_EXPORTER=true;
                shift ;;
            --skip-provisioning) SKIP_PROVISIONING=true; shift ;;
            --version) COMPONENT_VERSION="$2"; shift 2 ;;
            --mysql-password) MYSQL_PASSWORD_ARG="$2"; shift 2 ;;
            --grafana-user) GRAFANA_USER_ARG="$2"; shift 2 ;;
            --grafana-password) GRAFANA_PASSWORD_ARG="$2"; shift 2 ;;
            --grafana-url) GRAFANA_URL_ARG="$2"; shift 2 ;;
            --pm2-user) PM2_USER_ARG="$2"; shift 2 ;;
            --) shift; break ;;
            *) log_error "Internal error! Unexpected option: $1"; exit 1 ;;
        esac
    done

    if [[ $# -ne 0 ]]; then
        log_error "Unexpected arguments: $*"
        display_help
        exit 1
    fi
    if [[ "$ACTION" == "install" && "$INSTALL_PM2_EXPORTER" == "true" && -z "$PM2_USER_ARG" ]]; then
        read -p "Enter the username for the PM2 application user: " PM2_USER_ARG
        if [[ -z "$PM2_USER_ARG" ]]; then
            log_error "PM2 user cannot be empty when installing PM2 exporter."
            exit 1
        fi
        if ! id -u "$PM2_USER_ARG" > /dev/null 2>&1; then
             log_error "User '$PM2_USER_ARG' does not exist. Please create the user first."
             exit 1
        fi
    fi


    if [[ "${INSTALL_PROMETHEUS}" == "false" && "${INSTALL_GRAFANA}" == "false" && \
          "${INSTALL_NODE_EXPORTER}" == "false" && "${INSTALL_BLACKBOX_EXPORTER}" == "false" && \
          "${INSTALL_MYSQL_EXPORTER}" == "false" && "${INSTALL_PM2_EXPORTER}" == "false" ]]; then
        log_error "No components selected for ${ACTION}."
        display_help
        exit 1
    fi
}

check_and_export_variables() {
    export MYSQL_EXPORTER_PASSWORD="${MYSQL_PASSWORD_ARG:-${MYSQL_EXPORTER_PASSWORD:-}}"
    export GRAFANA_ADMIN_USER="${GRAFANA_USER_ARG:-${GRAFANA_ADMIN_USER:-admin}}"
    export GRAFANA_ADMIN_PASSWORD="${GRAFANA_PASSWORD_ARG:-${GRAFANA_ADMIN_PASSWORD:-}}"
    export GRAFANA_ROOT_URL="${GRAFANA_URL_ARG:-${GRAFANA_ROOT_URL:-}}"

    if [[ "$ACTION" == "install" ]]; then
        if [[ "${INSTALL_MYSQL_EXPORTER}" == "true" ]] && [[ -z "${MYSQL_EXPORTER_PASSWORD}" ]]; then
            handle_error "MySQL Exporter installation requires --mysql-password argument or MYSQL_EXPORTER_PASSWORD environment variable."
        fi
        if [[ "${INSTALL_GRAFANA}" == "true" ]] && [[ -z "${GRAFANA_ADMIN_PASSWORD}" ]]; then
            handle_error "Grafana installation requires --grafana-password argument or GRAFANA_ADMIN_PASSWORD environment variable."
        fi
    fi
}

install_components() {
    log_info "Starting installation process..."
    init_script

    if [[ "${INSTALL_PROMETHEUS}" == "true" ]]; then
        install_prometheus "${COMPONENT_VERSION}"
    fi

    if [[ "${INSTALL_GRAFANA}" == "true" ]]; then
        install_grafana
        if [[ "${SKIP_PROVISIONING}" == "false" ]]; then
            download_file_if_missing "provisioning/alerting/alert-rules.json" "${PROVISIONING_DIR}/alerting/alert-rules.json"
            download_file_if_missing "provisioning/alerting/contact-points.json" "${PROVISIONING_DIR}/alerting/contact-points.json"
            download_file_if_missing "provisioning/alerting/policies.json" "${PROVISIONING_DIR}/alerting/policies.json"
            download_file_if_missing "provisioning/dashboards/dashboard-alerts.json" "${PROVISIONING_DIR}/dashboards/dashboard-alerts.json"
            download_file_if_missing "provisioning/dashboards/dashboard-duplicati.json" "${PROVISIONING_DIR}/dashboards/dashboard-duplicati.json"
            download_file_if_missing "provisioning/dashboards/dashboard-mysql.json" "${PROVISIONING_DIR}/dashboards/dashboard-mysql.json"
            download_file_if_missing "provisioning/dashboards/dashboard-node.json" "${PROVISIONING_DIR}/dashboards/dashboard-node.json"

            provision_grafana "${PROVISIONING_DIR}"
        fi
    fi

    if [[ "${INSTALL_NODE_EXPORTER}" == "true" ]]; then
        install_node_exporter "${COMPONENT_VERSION}"
    fi

    if [[ "${INSTALL_BLACKBOX_EXPORTER}" == "true" ]]; then
        install_blackbox_exporter "${COMPONENT_VERSION}"
    fi

    if [[ "${INSTALL_MYSQL_EXPORTER}" == "true" ]]; then
        install_mysql_exporter "${COMPONENT_VERSION}" "monitoring" "${MYSQL_EXPORTER_PASSWORD}"
    fi

    if [[ "${INSTALL_PM2_EXPORTER}" == "true" ]]; then
        install_pm2_exporter "${PM2_USER_ARG}"
    fi
}

uninstall_components() {
    log_info "Starting uninstallation process..."
    check_root


    # Uninstall PM2 Exporter - Temporarily commented out due to hang issues
    if [[ "${INSTALL_PM2_EXPORTER}" == "true" ]]; then
        uninstall_pm2_exporter "${PM2_USER_ARG}"
    fi

    if [[ "${INSTALL_MYSQL_EXPORTER}" == "true" ]]; then
        uninstall_mysql_exporter
    fi

    if [[ "${INSTALL_BLACKBOX_EXPORTER}" == "true" ]]; then
        uninstall_blackbox_exporter
    fi

    if [[ "${INSTALL_NODE_EXPORTER}" == "true" ]]; then
        uninstall_node_exporter
    fi

    if [[ "${INSTALL_GRAFANA}" == "true" ]]; then
        uninstall_grafana
    fi

    if [[ "${INSTALL_PROMETHEUS}" == "true" ]]; then
        uninstall_prometheus
    fi

    log_info "Uninstallation finished. Review logs for any warnings."
    log_warning "Manually installed dependencies (e.g., mysql-client, nodejs, npm) are not removed."
    log_warning "Manually created MySQL users (e.g., for mysql_exporter) are not removed."
    log_warning "Data directories might persist if you chose not to remove them during uninstall prompts."
}

display_status() {
    log_info "-------------------- Installation Status --------------------"

    local prometheus_addr="127.0.0.1:${PROMETHEUS_PORT:-9090}"
    local grafana_addr="${GRAFANA_BIND_ADDR:-127.0.0.1}:${GRAFANA_DEFAULT_PORT:-3000}"

    if [[ "${INSTALL_PROMETHEUS}" == "true" ]]; then
        if check_prometheus; then
             log_info "Prometheus URL: http://${prometheus_addr}"
        fi
    fi

    if [[ "${INSTALL_GRAFANA}" == "true" ]]; then
        if check_grafana; then
            log_info "Grafana URL: http://${grafana_addr}"
            log_info "Grafana Admin User: ${GRAFANA_ADMIN_USER}"
            log_info "Grafana Admin Password: Set via --grafana-password or GRAFANA_ADMIN_PASSWORD env var"
            if [[ -n "${GRAFANA_ROOT_URL:-}" ]] && [[ "${GRAFANA_ROOT_URL}" != "http://${grafana_addr}/" ]]; then
                 log_info "Grafana External URL: ${GRAFANA_ROOT_URL}"
            else
                 log_warning "Grafana External URL not explicitly set (--grafana-url or GRAFANA_ROOT_URL). Alert links might use internal address."
            fi
        fi
    fi

    if [[ "${INSTALL_NODE_EXPORTER}" == "true" ]]; then
        check_node_exporter
    fi

    if [[ "${INSTALL_BLACKBOX_EXPORTER}" == "true" ]]; then
        check_blackbox_exporter
    fi

    if [[ "${INSTALL_MYSQL_EXPORTER}" == "true" ]]; then
        if check_mysql_exporter; then
             log_info "MySQL Exporter user: monitoring (Manual creation required, see README)"
             log_info "MySQL Exporter config file: ${MYSQL_EXPORTER_CONFIG_FILE:-/etc/.mysqld_exporter.cnf}"
        fi
    fi

    if [[ "${INSTALL_PM2_EXPORTER}" == "true" ]]; then
        check_pm2_exporter "${PM2_USER_ARG}"
    fi

    log_success "-------------------- Monitoring stack setup finished --------------------"
}

main() {
    parse_arguments "$@"

    check_and_export_variables

    if [[ "$ACTION" == "install" ]]; then
        install_components
        display_status
    elif [[ "$ACTION" == "uninstall" ]]; then
        uninstall_components
        log_success "Uninstallation process completed."
    else
        log_error "Invalid action: ${ACTION}"
        exit 1
    fi
}

main "$@"