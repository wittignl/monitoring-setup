#!/bin/bash
#
# Blackbox Exporter installation functions
#

# Default values
BLACKBOX_EXPORTER_VERSION="0.25.0"
BLACKBOX_EXPORTER_USER="prometheus"
BLACKBOX_EXPORTER_GROUP="prometheus"
BLACKBOX_EXPORTER_PORT="9115"
BLACKBOX_EXPORTER_CONFIG_DIR="/etc/blackbox_exporter"

# Install Blackbox Exporter
install_blackbox_exporter() {
    local version=${1:-$BLACKBOX_EXPORTER_VERSION}

    log_info "Installing Blackbox Exporter version ${version}"

    # Ensure prometheus user exists
    create_user "${BLACKBOX_EXPORTER_USER}"

    # Create configuration directory
    create_directory "${BLACKBOX_EXPORTER_CONFIG_DIR}" "${BLACKBOX_EXPORTER_USER}" "${BLACKBOX_EXPORTER_GROUP}" "0755"

    # Download and extract Blackbox Exporter
    cd "${TEMP_DIR}"
    local blackbox_exporter_archive="blackbox_exporter-${version}.linux-${ARCH}.tar.gz"
    local blackbox_exporter_url="https://github.com/prometheus/blackbox_exporter/releases/download/v${version}/${blackbox_exporter_archive}"

    download_file "${blackbox_exporter_url}" "${blackbox_exporter_archive}"
    extract_archive "${blackbox_exporter_archive}" "${TEMP_DIR}"

    # Move files to the correct locations
    local extracted_dir="blackbox_exporter-${version}.linux-${ARCH}"
    cd "${extracted_dir}"

    log_info "Moving Blackbox Exporter binary to /usr/local/bin"
    mv blackbox_exporter /usr/local/bin/
    chown "${BLACKBOX_EXPORTER_USER}:${BLACKBOX_EXPORTER_GROUP}" /usr/local/bin/blackbox_exporter
    chmod 755 /usr/local/bin/blackbox_exporter

    # Copy configuration file
    log_info "Copying Blackbox Exporter configuration"
    if [[ -f "blackbox.yml" ]]; then
        cp blackbox.yml "${BLACKBOX_EXPORTER_CONFIG_DIR}/"
        chown "${BLACKBOX_EXPORTER_USER}:${BLACKBOX_EXPORTER_GROUP}" "${BLACKBOX_EXPORTER_CONFIG_DIR}/blackbox.yml"
        chmod 644 "${BLACKBOX_EXPORTER_CONFIG_DIR}/blackbox.yml"
    else
        # Create default configuration if not found
        create_default_blackbox_config
    fi

    # Create systemd service
    create_blackbox_exporter_service

    # Reload systemd, enable and start Blackbox Exporter
    reload_systemd
    enable_service "blackbox_exporter"
    start_service "blackbox_exporter"

    # Check if Blackbox Exporter is running
    check_service_status "blackbox_exporter"

    log_success "Blackbox Exporter ${version} installed successfully"
}

# Create default Blackbox Exporter configuration
create_default_blackbox_config() {
    log_info "Creating default Blackbox Exporter configuration"

    cat > "${BLACKBOX_EXPORTER_CONFIG_DIR}/blackbox.yml" << EOF
modules:
  http_2xx:
    prober: http
    http:
      preferred_ip_protocol: "ip4"
  http_post_2xx:
    prober: http
    http:
      method: POST
  tcp_connect:
    prober: tcp
  pop3s_banner:
    prober: tcp
    tcp:
      query_response:
      - expect: "^+OK"
      tls: true
      tls_config:
        insecure_skip_verify: false
  grpc:
    prober: grpc
    grpc:
      tls: true
      preferred_ip_protocol: "ip4"
  grpc_plain:
    prober: grpc
    grpc:
      tls: false
      service: "service1"
  ssh_banner:
    prober: tcp
    tcp:
      query_response:
      - expect: "^SSH-2.0-"
      - send: "SSH-2.0-blackbox-ssh-check"
  irc_banner:
    prober: tcp
    tcp:
      query_response:
      - send: "NICK prober"
      - send: "USER prober prober prober :prober"
      - expect: "PING :([^ ]+)"
        send: "PONG ${1}"
      - expect: "^:[^ ]+ 001"
  icmp:
    prober: icmp
  icmp_ttl5:
    prober: icmp
    timeout: 5s
    icmp:
      ttl: 5
  http_prometheus:
    prober: http
    timeout: 5s
    http:
      method: GET
      valid_http_versions: ["HTTP/1.1", "HTTP/2"]
      fail_if_ssl: false
      fail_if_not_ssl: false
EOF

    chown "${BLACKBOX_EXPORTER_USER}:${BLACKBOX_EXPORTER_GROUP}" "${BLACKBOX_EXPORTER_CONFIG_DIR}/blackbox.yml"
    chmod 644 "${BLACKBOX_EXPORTER_CONFIG_DIR}/blackbox.yml"

    log_success "Default Blackbox Exporter configuration created"
}

# Create Blackbox Exporter systemd service
create_blackbox_exporter_service() {
    local service_content="[Unit]
Description=Prometheus Blackbox Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=${BLACKBOX_EXPORTER_USER}
Group=${BLACKBOX_EXPORTER_GROUP}
ExecStart=/usr/local/bin/blackbox_exporter \\
    --config.file=${BLACKBOX_EXPORTER_CONFIG_DIR}/blackbox.yml \\
    --web.listen-address=:${BLACKBOX_EXPORTER_PORT}
Restart=always

[Install]
WantedBy=multi-user.target"

    create_systemd_service "blackbox_exporter" "${service_content}"
}

# Add domain to Prometheus configuration for monitoring
add_blackbox_target() {
    local domain=$1
    local module=${2:-"http_2xx"}
    local config_file="/etc/prometheus/prometheus.yml"

    log_info "Adding Blackbox Exporter target for domain: ${domain}"

    # Check if Prometheus is installed
    if [[ ! -f "${config_file}" ]]; then
        log_warning "Prometheus configuration file not found. Cannot add Blackbox target."
        return 1
    fi

    # Check if blackbox job already exists
    if grep -q "job_name: 'blackbox-exporter'" "${config_file}"; then
        # Add target to existing job
        local target_line="          - ${domain}"
        if ! grep -q "${target_line}" "${config_file}"; then
            sed -i "/targets:/a\\${target_line}" "${config_file}"
            log_success "Added ${domain} to existing Blackbox job"
        else
            log_warning "Target ${domain} already exists in Blackbox job"
        fi
    else
        # Create new blackbox job
        local blackbox_config="  - job_name: 'blackbox-exporter'
    metrics_path: /probe
    params:
      module: [${module}]
    static_configs:
      - targets:
          - ${domain}
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:${BLACKBOX_EXPORTER_PORT}"

        # Add to prometheus.yml
        add_yaml_block "${config_file}" "${blackbox_config}" "scrape_configs"
        log_success "Added new Blackbox job with target ${domain}"
    fi

    # Restart Prometheus to apply changes
    if systemctl is-active --quiet prometheus; then
        restart_service "prometheus"
    fi
}

# Check Blackbox Exporter status
check_blackbox_exporter() {
    log_info "Checking Blackbox Exporter status"

    # Check if Blackbox Exporter is installed
    if [[ ! -f "/usr/local/bin/blackbox_exporter" ]]; then
        log_error "Blackbox Exporter is not installed"
        return 1
    fi

    # Check if Blackbox Exporter service is running
    if ! systemctl is-active --quiet blackbox_exporter; then
        log_error "Blackbox Exporter service is not running"
        return 1
    fi

    # Check if Blackbox Exporter is responding
    if ! curl -s "http://localhost:${BLACKBOX_EXPORTER_PORT}/metrics" &>/dev/null; then
        log_error "Blackbox Exporter is not responding"
        return 1
    fi

    log_success "Blackbox Exporter is installed and running"
    return 0
}

# Uninstall Blackbox Exporter
uninstall_blackbox_exporter() {
    log_info "Uninstalling Blackbox Exporter"

    # Stop and disable service
    if systemctl is-active --quiet blackbox_exporter; then
        systemctl stop blackbox_exporter
    fi
    if systemctl is-enabled --quiet blackbox_exporter; then
        systemctl disable blackbox_exporter
    fi

    # Remove service file
    if [[ -f "/etc/systemd/system/blackbox_exporter.service" ]]; then
        rm -f "/etc/systemd/system/blackbox_exporter.service"
        systemctl daemon-reload
    fi

    # Remove binary
    if [[ -f "/usr/local/bin/blackbox_exporter" ]]; then
        rm -f "/usr/local/bin/blackbox_exporter"
    fi

    # Ask if configuration should be removed
    read -p "Remove Blackbox Exporter configuration? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Remove configuration
        if [[ -d "${BLACKBOX_EXPORTER_CONFIG_DIR}" ]]; then
            rm -rf "${BLACKBOX_EXPORTER_CONFIG_DIR}"
        fi
    fi

    # Remove from Prometheus configuration if Prometheus is installed
    if [[ -f "/etc/prometheus/prometheus.yml" ]]; then
        log_info "Removing Blackbox Exporter from Prometheus configuration"
        sed -i '/job_name: .blackbox./,+12d' /etc/prometheus/prometheus.yml

        # Restart Prometheus if it's running
        if systemctl is-active --quiet prometheus; then
            systemctl restart prometheus
        fi
    fi

    log_success "Blackbox Exporter uninstalled"
}