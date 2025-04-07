#!/bin/bash
#
# Node Exporter installation functions
#

NODE_EXPORTER_VERSION="1.8.2"
NODE_EXPORTER_USER="prometheus"
NODE_EXPORTER_GROUP="prometheus"
NODE_EXPORTER_PORT="9100"

install_node_exporter() {
    local version=${1:-$NODE_EXPORTER_VERSION}

    log_info "Installing Node Exporter version ${version}"

    create_user "${NODE_EXPORTER_USER}"

    cd "${TEMP_DIR}"
    local node_exporter_archive="node_exporter-${version}.linux-${ARCH}.tar.gz"
    local node_exporter_url="https://github.com/prometheus/node_exporter/releases/download/v${version}/${node_exporter_archive}"

    download_file "${node_exporter_url}" "${node_exporter_archive}"
    extract_archive "${node_exporter_archive}" "${TEMP_DIR}"

    local extracted_dir="node_exporter-${version}.linux-${ARCH}"
    cd "${extracted_dir}"

    log_info "Moving Node Exporter binary to /usr/local/bin"
    mv node_exporter /usr/local/bin/
    chown "${NODE_EXPORTER_USER}:${NODE_EXPORTER_GROUP}" /usr/local/bin/node_exporter
    chmod 755 /usr/local/bin/node_exporter

    create_node_exporter_service

    reload_systemd
    enable_service "node_exporter"
    start_service "node_exporter"

    check_service_status "node_exporter"

    if command_exists prometheus; then
        add_scrape_config "node_exporter" "localhost:${NODE_EXPORTER_PORT}"
    else
        log_warning "Prometheus is not installed. You will need to configure it manually to scrape Node Exporter."
    fi

    log_success "Node Exporter ${version} installed successfully"
}

create_node_exporter_service() {
    local service_content="[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=${NODE_EXPORTER_USER}
Group=${NODE_EXPORTER_GROUP}
ExecStart=/usr/local/bin/node_exporter \\
    --collector.logind \\
    --web.listen-address=:${NODE_EXPORTER_PORT}
Restart=always

[Install]
WantedBy=multi-user.target"

    create_systemd_service "node_exporter" "${service_content}"
}

check_node_exporter() {
    log_info "Checking Node Exporter status"

    if [[ ! -f "/usr/local/bin/node_exporter" ]]; then
        log_error "Node Exporter is not installed"
        return 1
    fi

    if ! systemctl is-active --quiet node_exporter; then
        log_error "Node Exporter service is not running"
        return 1
    fi

    if ! curl -s "http://localhost:${NODE_EXPORTER_PORT}/metrics" &>/dev/null; then
        log_error "Node Exporter is not responding"
        return 1
    fi

    log_success "Node Exporter is installed and running"
    return 0
}

uninstall_node_exporter() {
    log_info "Uninstalling Node Exporter"

    if systemctl is-active --quiet node_exporter; then
        systemctl stop node_exporter
    fi
    if systemctl is-enabled --quiet node_exporter; then
        systemctl disable node_exporter
    fi

    if [[ -f "/etc/systemd/system/node_exporter.service" ]]; then
        rm -f "/etc/systemd/system/node_exporter.service"
        systemctl daemon-reload
    fi

    if [[ -f "/usr/local/bin/node_exporter" ]]; then
        rm -f "/usr/local/bin/node_exporter"
    fi

    if [[ -f "/etc/prometheus/prometheus.yml" ]]; then
        log_info "Removing Node Exporter from Prometheus configuration"

        if type remove_scrape_config &>/dev/null; then
            remove_scrape_config "node_exporter"
        else
            sed -i '/job_name: .node_exporter./,+3d' /etc/prometheus/prometheus.yml

            if systemctl is-active --quiet prometheus; then
                systemctl restart prometheus
            fi
        fi
    fi

    log_success "Node Exporter uninstalled"
}