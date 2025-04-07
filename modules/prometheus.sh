#!/bin/bash
#
# Prometheus installation functions
#

PROMETHEUS_VERSION="3.1.0"
PROMETHEUS_USER="prometheus"
PROMETHEUS_GROUP="prometheus"
PROMETHEUS_PORT="9090"
PROMETHEUS_CONFIG_DIR="/etc/prometheus"
PROMETHEUS_DATA_DIR="/var/lib/prometheus"
PROMETHEUS_BIN_DIR="/usr/local/bin"

install_prometheus() {
    local version=${1:-$PROMETHEUS_VERSION}

    log_info "Installing Prometheus version ${version}"

    create_user "${PROMETHEUS_USER}"

    create_directory "${PROMETHEUS_CONFIG_DIR}" "${PROMETHEUS_USER}" "${PROMETHEUS_GROUP}" "0750"
    create_directory "${PROMETHEUS_CONFIG_DIR}/conf.d" "${PROMETHEUS_USER}" "${PROMETHEUS_GROUP}" "0750"
    create_directory "${PROMETHEUS_DATA_DIR}" "${PROMETHEUS_USER}" "${PROMETHEUS_GROUP}" "0750"

    cd "${TEMP_DIR}"
    local prometheus_archive="prometheus-${version}.linux-${ARCH}.tar.gz"
    local prometheus_url="https://github.com/prometheus/prometheus/releases/download/v${version}/${prometheus_archive}"

    download_file "${prometheus_url}" "${prometheus_archive}"
    extract_archive "${prometheus_archive}" "${TEMP_DIR}"

    local extracted_dir="prometheus-${version}.linux-${ARCH}"
    cd "${extracted_dir}"

    log_info "Moving Prometheus binaries to ${PROMETHEUS_BIN_DIR}"
    mv prometheus promtool "${PROMETHEUS_BIN_DIR}/"
    chown "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${PROMETHEUS_BIN_DIR}/prometheus" "${PROMETHEUS_BIN_DIR}/promtool"
    chmod 755 "${PROMETHEUS_BIN_DIR}/prometheus" "${PROMETHEUS_BIN_DIR}/promtool"

    log_info "Moving Prometheus configuration files to ${PROMETHEUS_CONFIG_DIR}"
    if [[ -d "consoles" ]]; then
        cp -r consoles "${PROMETHEUS_CONFIG_DIR}/"
    fi
    if [[ -d "console_libraries" ]]; then
        cp -r console_libraries "${PROMETHEUS_CONFIG_DIR}/"
    fi

    create_base_prometheus_config

    chown -R "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${PROMETHEUS_CONFIG_DIR}/consoles" "${PROMETHEUS_CONFIG_DIR}/console_libraries" 2>/dev/null || true
    chown "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${PROMETHEUS_CONFIG_DIR}/prometheus.yml"

    create_prometheus_service

    reload_systemd
    enable_service "prometheus"
    start_service "prometheus"

    check_service_status "prometheus"

    log_success "Prometheus ${version} installed successfully"
}

create_prometheus_service() {
    local service_content="[Unit]
Description=Prometheus
Documentation=https://prometheus.io/docs/introduction/overview/
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=${PROMETHEUS_USER}
Group=${PROMETHEUS_GROUP}
ExecReload=/bin/kill -HUP \$MAINPID
ExecStart=${PROMETHEUS_BIN_DIR}/prometheus \\
    --config.file=${PROMETHEUS_CONFIG_DIR}/prometheus.yml \\
    --storage.tsdb.path=${PROMETHEUS_DATA_DIR} \\
    --web.console.templates=${PROMETHEUS_CONFIG_DIR}/consoles \\
    --web.console.libraries=${PROMETHEUS_CONFIG_DIR}/console_libraries \\
    --web.listen-address=127.0.0.1:${PROMETHEUS_PORT}
SyslogIdentifier=prometheus
Restart=always

[Install]
WantedBy=multi-user.target"

    create_systemd_service "prometheus" "${service_content}"
}

create_base_prometheus_config() {
    local config_file="${PROMETHEUS_CONFIG_DIR}/prometheus.yml"
    local config_file="${PROMETHEUS_CONFIG_DIR}/prometheus.yml"

    if [[ ! -f "${config_file}" ]]; then
        log_info "Creating base Prometheus configuration file: ${config_file}"
        cat > "${config_file}" << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['127.0.0.1:${PROMETHEUS_PORT}']

  - job_name: 'file_sd_exporters'
    file_sd_configs:
      - files:
          - '${PROMETHEUS_CONFIG_DIR}/conf.d/*.yml'
          - '${PROMETHEUS_CONFIG_DIR}/conf.d/*.json'
        refresh_interval: 1m
EOF
        chown "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${config_file}"
        chmod 644 "${config_file}"
        log_success "Created base Prometheus configuration with file_sd"
    else
        log_info "Prometheus configuration file ${config_file} already exists, skipping creation."
        # Ensure permissions are still correct in case they were changed
        chown "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${config_file}"
        chmod 644 "${config_file}"
    fi

}

check_prometheus() {
    log_info "Checking Prometheus status"

    if [[ ! -f "${PROMETHEUS_BIN_DIR}/prometheus" ]]; then
        log_error "Prometheus is not installed"
        return 1
    fi

    if ! systemctl is-active --quiet prometheus; then
        log_error "Prometheus service is not running"
        return 1
    fi

    if ! curl --fail -s "http://127.0.0.1:${PROMETHEUS_PORT}/-/healthy" &>/dev/null; then
        log_error "Prometheus is not responding"
        return 1
    fi

    log_success "Prometheus is installed and running"
    return 0
}

uninstall_prometheus() {
    log_info "Uninstalling Prometheus"

    if systemctl is-active --quiet prometheus; then
        systemctl stop prometheus
    fi
    if systemctl is-enabled --quiet prometheus; then
        systemctl disable prometheus
    fi

    if [[ -f "/etc/systemd/system/prometheus.service" ]]; then
        rm -f "/etc/systemd/system/prometheus.service"
        systemctl daemon-reload
    fi

    if [[ -f "${PROMETHEUS_BIN_DIR}/prometheus" ]]; then
        rm -f "${PROMETHEUS_BIN_DIR}/prometheus"
    fi
    if [[ -f "${PROMETHEUS_BIN_DIR}/promtool" ]]; then
        rm -f "${PROMETHEUS_BIN_DIR}/promtool"
    fi

    read -p "Remove Prometheus data and configuration? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ -d "${PROMETHEUS_DATA_DIR}" ]]; then
            rm -rf "${PROMETHEUS_DATA_DIR}"
        fi
        if [[ -d "${PROMETHEUS_CONFIG_DIR}" ]]; then
            rm -rf "${PROMETHEUS_CONFIG_DIR}"
        fi
    fi

    # Remove Prometheus user
    if id "${PROMETHEUS_USER}" &>/dev/null; then
        log_info "Removing Prometheus system user '${PROMETHEUS_USER}'"
        userdel -r "${PROMETHEUS_USER}"
        if [[ $? -ne 0 ]]; then
            log_warning "Failed to remove user '${PROMETHEUS_USER}'. Manual removal might be needed."
        else
            log_success "Removed Prometheus user '${PROMETHEUS_USER}'"
        fi
    else
        log_info "Prometheus user '${PROMETHEUS_USER}' does not exist, skipping removal."
    fi

    log_success "Prometheus uninstalled"
}