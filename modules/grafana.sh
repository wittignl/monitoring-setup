#!/bin/bash
#
# Grafana installation functions
#

GRAFANA_DEFAULT_PORT="3000"
GRAFANA_BIND_ADDR="0.0.0.0"
GRAFANA_CONFIG_DIR="/etc/grafana"
GRAFANA_PROVISIONING_DIR="${GRAFANA_CONFIG_DIR}/provisioning"

install_grafana() {
    log_info "Installing Grafana"

    install_packages apt-transport-https software-properties-common wget

    log_info "Importing Grafana GPG key"
    mkdir -p /etc/apt/keyrings/
    wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null

    local grafana_repo_file="/etc/apt/sources.list.d/grafana.list"
    if [[ ! -f "${grafana_repo_file}" ]]; then
        log_info "Adding Grafana repository"
        echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee "${grafana_repo_file}" > /dev/null
    else
        log_info "Grafana repository file already exists, skipping add."
    fi

    update_package_lists
    install_package grafana

    create_grafana_systemd_override

    configure_grafana

    log_info "Starting Grafana service"
    systemctl daemon-reload
    start_service grafana-server
    enable_service grafana-server

    check_service_status grafana-server

    log_success "Grafana installed successfully"
}

create_grafana_systemd_override() {
    local override_dir="/etc/systemd/system/grafana-server.service.d"
    local override_file="${override_dir}/override.conf"

    log_info "Creating Grafana systemd override file: ${override_file}"
    mkdir -p "${override_dir}"

    if [[ -z "${GRAFANA_ADMIN_USER:-}" ]]; then
        log_warning "GRAFANA_ADMIN_USER environment variable not set. Using default 'admin'."
        GRAFANA_ADMIN_USER="admin"
    fi
    if [[ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
        handle_error "GRAFANA_ADMIN_PASSWORD environment variable is not set. Cannot configure Grafana securely."
    fi
     if [[ -z "${GRAFANA_ROOT_URL:-}" ]]; then
        log_warning "GRAFANA_ROOT_URL environment variable not set. Using default http://${GRAFANA_BIND_ADDR}:${GRAFANA_DEFAULT_PORT}/"
        GRAFANA_ROOT_URL="http://${GRAFANA_BIND_ADDR}:${GRAFANA_DEFAULT_PORT}/"
    fi

    cat > "${override_file}" << EOF
[Service]
Environment="GF_SERVER_HTTP_ADDR=${GRAFANA_BIND_ADDR}"
Environment="GF_SERVER_HTTP_PORT=${GRAFANA_DEFAULT_PORT}"
Environment="GF_SERVER_ROOT_URL=${GRAFANA_ROOT_URL%/}"
Environment="GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER}"
Environment="GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}"
EOF

    chmod 644 "${override_file}"
    log_success "Grafana systemd override file created."

    reload_systemd
}


configure_grafana() {
    log_info "Ensuring Grafana provisioning directories exist"

    create_directory "${GRAFANA_PROVISIONING_DIR}/datasources" "grafana" "grafana" "0750"
    create_directory "${GRAFANA_PROVISIONING_DIR}/dashboards" "grafana" "grafana" "0750"
    create_directory "${GRAFANA_PROVISIONING_DIR}/alerting" "grafana" "grafana" "0750"

    log_success "Grafana provisioning directories ensured"
}

copy_provisioning_files() {
    local source_dir="$1"
    local dest_dir="$2"
    local file_pattern="$3"
    local owner="$4"
    local group="$5"
    local permissions="$6"
    local success_count=0
    local total_count=0

    if [[ ! -d "${dest_dir}" ]]; then
        mkdir -p "${dest_dir}"
        chown "${owner}:${group}" "${dest_dir}"
        chmod 750 "${dest_dir}"
    fi

    if [[ -d "${source_dir}" ]]; then
        local files=("${source_dir}"/${file_pattern})

        if [[ -f "${files[0]}" ]]; then
            for file in "${files[@]}"; do
                local filename=$(basename "${file}")
                total_count=$((total_count + 1))

                log_info "Copying ${filename} to ${dest_dir}"
                if cp "${file}" "${dest_dir}/"; then
                    chown "${owner}:${group}" "${dest_dir}/${filename}"
                    chmod "${permissions}" "${dest_dir}/${filename}"
                    success_count=$((success_count + 1))
                else
                    log_error "Failed to copy ${filename}"
                fi
            done

            log_success "Copied ${success_count}/${total_count} files to ${dest_dir}"
            return 0
        else
            log_warning "No files matching ${file_pattern} found in ${source_dir}"
            return 1
        fi
    else
        log_warning "Source directory ${source_dir} does not exist"
        return 1
    fi
}

provision_grafana() {
    local provisioning_source_dir="$1"

    if [[ -z "${provisioning_source_dir}" ]]; then
        log_error "Provisioning source directory not specified"
        return 1
    fi

    if [[ ! -d "${provisioning_source_dir}" ]]; then
        log_error "Provisioning source directory ${provisioning_source_dir} does not exist"
        return 1
    fi

    log_info "Provisioning Grafana with files from ${provisioning_source_dir}"

    if [[ ! -d "${GRAFANA_PROVISIONING_DIR}" ]]; then
        mkdir -p "${GRAFANA_PROVISIONING_DIR}"
        chown grafana:grafana "${GRAFANA_PROVISIONING_DIR}"
        chmod 750 "${GRAFANA_PROVISIONING_DIR}"
    fi

    log_info "Copying provisioning files to ${GRAFANA_PROVISIONING_DIR}"
    cp -R "${provisioning_source_dir}"/* "${GRAFANA_PROVISIONING_DIR}/"

    chown -R grafana:grafana "${GRAFANA_PROVISIONING_DIR}"
    find "${GRAFANA_PROVISIONING_DIR}" -type d -exec chmod 750 {} \;
    find "${GRAFANA_PROVISIONING_DIR}" -type f -exec chmod 640 {} \;

    if [[ -f "${GRAFANA_PROVISIONING_DIR}/datasources/prometheus.yml" ]] && [[ -n "${PROMETHEUS_PORT:-}" ]]; then
        log_info "Updating Prometheus port in datasource configuration"
        sed -i "s|localhost:[0-9]*|0.0.0.0:${PROMETHEUS_PORT:-9090}|g" "${GRAFANA_PROVISIONING_DIR}/datasources/prometheus.yml"
    fi

    if [[ -f "${GRAFANA_PROVISIONING_DIR}/dashboards/default.yml" ]]; then
        log_info "Updating dashboard provider path"
        sed -i "s|path:.*|path: ${GRAFANA_PROVISIONING_DIR}/dashboards|g" "${GRAFANA_PROVISIONING_DIR}/dashboards/default.yml"
    fi

    create_directory "${GRAFANA_PROVISIONING_DIR}/dashboards" "grafana" "grafana" "0750"

    if ls "${GRAFANA_PROVISIONING_DIR}/dashboards/dashboard-*.json" &>/dev/null; then
        log_info "Moving dashboard JSON files"
        mv "${GRAFANA_PROVISIONING_DIR}/dashboards/dashboard-*.json" "${GRAFANA_PROVISIONING_DIR}/dashboards/"
    fi

    restart_service grafana-server

    log_success "Grafana provisioning completed"
}

check_grafana() {
    log_info "Checking Grafana status"

    # Primary check: Is the service active?
    if ! systemctl is-active --quiet grafana-server; then
        # If service isn't active, check if it's installed at all
        if ! dpkg -l | grep -q grafana; then
             log_error "Grafana package is not installed"
        else
             log_error "Grafana service (grafana-server) is installed but not running"
        fi
        return 1
    fi

    # Secondary check: Is the API responding? (Optional, but good sanity check)
    if ! curl --fail -s "http://${GRAFANA_BIND_ADDR}:${GRAFANA_DEFAULT_PORT}/api/health" &>/dev/null; then
        log_warning "Grafana service is running, but API endpoint is not responding (check firewall or Grafana logs)"
        # We don't return 1 here because the service *is* running, which is the main point for the summary.
    fi

    log_success "Grafana is installed and running"
    return 0
}

uninstall_grafana() {
    log_info "Uninstalling Grafana"

    if systemctl is-active --quiet grafana-server; then
        systemctl stop grafana-server
    fi
    if systemctl is-enabled --quiet grafana-server; then
        systemctl disable grafana-server
    fi

    apt-get remove -y grafana

    read -p "Remove Grafana data and configuration? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        apt-get purge -y grafana
        rm -rf "${GRAFANA_CONFIG_DIR}"
        rm -rf /var/lib/grafana
        rm -f /etc/systemd/system/grafana-server.service.d/override.conf
    fi

    rm -f /etc/apt/sources.list.d/grafana.list
    rm -f /etc/apt/keyrings/grafana.gpg

    log_success "Grafana uninstalled"
}