#!/bin/bash
#
# Grafana installation functions
#

# Default values
GRAFANA_PORT="3000"
GRAFANA_CONFIG_DIR="/etc/grafana"
GRAFANA_PROVISIONING_DIR="${GRAFANA_CONFIG_DIR}/provisioning"

# Install Grafana
install_grafana() {
    log_info "Installing Grafana"

    # Install dependencies
    install_packages apt-transport-https software-properties-common wget

    # Import GPG key
    log_info "Importing Grafana GPG key"
    mkdir -p /etc/apt/keyrings/
    wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null

    # Add stable release repository
    log_info "Adding Grafana repository"
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee -a /etc/apt/sources.list.d/grafana.list

    # Update and install
    update_package_lists
    install_package grafana

    # Configure Grafana
    configure_grafana

    # Start and enable Grafana
    log_info "Starting Grafana service"
    systemctl daemon-reload
    start_service grafana-server
    enable_service grafana-server

    # Check if Grafana is running
    check_service_status grafana-server

    log_success "Grafana installed successfully"
}

# Configure Grafana
configure_grafana() {
    log_info "Configuring Grafana"

    # Backup existing configuration
    backup_config_file "${GRAFANA_CONFIG_DIR}/grafana.ini"

    # Ensure port is set correctly
    if grep -q "^;http_port = 3000" "${GRAFANA_CONFIG_DIR}/grafana.ini"; then
        log_info "Setting Grafana port to ${GRAFANA_PORT}"
        sed -i "s/^;http_port = 3000/http_port = ${GRAFANA_PORT}/" "${GRAFANA_CONFIG_DIR}/grafana.ini"
    fi

    # Set external URL if GRAFANA_EXTERNAL_URL is provided
    if [[ -n "${GRAFANA_EXTERNAL_URL:-}" ]]; then
        log_info "Setting Grafana root_url to ${GRAFANA_EXTERNAL_URL}"
        # Ensure the [server] section exists - add if not found
        if ! grep -q "^\\[server\\]" "${GRAFANA_CONFIG_DIR}/grafana.ini"; then
            log_info "Adding [server] section to grafana.ini"
            echo -e "\n[server]" >> "${GRAFANA_CONFIG_DIR}/grafana.ini"
        fi
        # Check if root_url is commented out
        if grep -q "^;root_url = " "${GRAFANA_CONFIG_DIR}/grafana.ini"; then
            # Uncomment and set the value, ensuring no duplicate slashes if GRAFANA_EXTERNAL_URL ends with /
            sed -i "s|^;root_url = .*|root_url = ${GRAFANA_EXTERNAL_URL%/}|" "${GRAFANA_CONFIG_DIR}/grafana.ini"
        # Check if root_url is already set (uncommented)
        elif grep -q "^root_url = " "${GRAFANA_CONFIG_DIR}/grafana.ini"; then
             # Update the existing value
             sed -i "s|^root_url = .*|root_url = ${GRAFANA_EXTERNAL_URL%/}|" "${GRAFANA_CONFIG_DIR}/grafana.ini"
        else
            # Add root_url under the [server] section if it doesn't exist at all
             log_info "Adding root_url to [server] section in grafana.ini"
             sed -i "/^\\[server\\]/a root_url = ${GRAFANA_EXTERNAL_URL%/}" "${GRAFANA_CONFIG_DIR}/grafana.ini"
        fi
    else
        log_warning "GRAFANA_EXTERNAL_URL environment variable not set. Alert links might use localhost."
    fi

    # Create provisioning directories if they don't exist
    create_directory "${GRAFANA_PROVISIONING_DIR}/datasources" "grafana" "grafana" "0750"
    create_directory "${GRAFANA_PROVISIONING_DIR}/dashboards" "grafana" "grafana" "0750"
    create_directory "${GRAFANA_PROVISIONING_DIR}/alerting" "grafana" "grafana" "0750"

    log_success "Grafana configured"
}

# Copy provisioning files from source to destination
copy_provisioning_files() {
    local source_dir="$1"
    local dest_dir="$2"
    local file_pattern="$3"
    local owner="$4"
    local group="$5"
    local permissions="$6"
    local success_count=0
    local total_count=0

    # Create destination directory if it doesn't exist
    if [[ ! -d "${dest_dir}" ]]; then
        mkdir -p "${dest_dir}"
        chown "${owner}:${group}" "${dest_dir}"
        chmod 750 "${dest_dir}"
    fi

    # Find and copy files matching the pattern
    if [[ -d "${source_dir}" ]]; then
        # Get list of files matching pattern
        local files=("${source_dir}"/${file_pattern})

        # Check if files exist
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

# Process environment variables in files
process_env_vars() {
    local file="$1"
    local var_name="$2"
    local var_value="$3"

    if [[ -f "${file}" ]] && [[ -n "${var_value}" ]]; then
        log_info "Replacing \${${var_name}} with its value in ${file}"
        sed -i "s|\${${var_name}}|${var_value}|g" "${file}"
        return 0
    elif [[ -f "${file}" ]] && [[ -z "${var_value}" ]]; then
        log_warning "${var_name} environment variable not set. You will need to configure this manually."
        return 1
    else
        log_error "File ${file} does not exist"
        return 2
    fi
}

# Provision Grafana
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

    # Ensure the destination directory exists
    if [[ ! -d "${GRAFANA_PROVISIONING_DIR}" ]]; then
        mkdir -p "${GRAFANA_PROVISIONING_DIR}"
        chown grafana:grafana "${GRAFANA_PROVISIONING_DIR}"
        chmod 750 "${GRAFANA_PROVISIONING_DIR}"
    fi

    # Recursively copy the entire provisioning directory
    log_info "Copying provisioning files to ${GRAFANA_PROVISIONING_DIR}"
    cp -R "${provisioning_source_dir}"/* "${GRAFANA_PROVISIONING_DIR}/"

    # Set proper ownership and permissions
    chown -R grafana:grafana "${GRAFANA_PROVISIONING_DIR}"
    find "${GRAFANA_PROVISIONING_DIR}" -type d -exec chmod 750 {} \;
    find "${GRAFANA_PROVISIONING_DIR}" -type f -exec chmod 640 {} \;

    # Process environment variables in prometheus.yml if needed
    if [[ -f "${GRAFANA_PROVISIONING_DIR}/datasources/prometheus.yml" ]] && [[ -n "${PROMETHEUS_PORT:-}" ]]; then
        log_info "Updating Prometheus port in datasource configuration"
        sed -i "s|localhost:[0-9]*|localhost:${PROMETHEUS_PORT:-9095}|g" "${GRAFANA_PROVISIONING_DIR}/datasources/prometheus.yml"
    fi

    # Update path in default.yml if needed
    if [[ -f "${GRAFANA_PROVISIONING_DIR}/dashboards/default.yml" ]]; then
        log_info "Updating dashboard provider path"
        sed -i "s|path:.*|path: ${GRAFANA_PROVISIONING_DIR}/dashboards|g" "${GRAFANA_PROVISIONING_DIR}/dashboards/default.yml"
    fi

    # Create dashboards/json directory if it doesn't exist
    create_directory "${GRAFANA_PROVISIONING_DIR}/dashboards" "grafana" "grafana" "0750"

    # Move dashboard JSON files if they exist in the dashboards directory
    if ls "${GRAFANA_PROVISIONING_DIR}/dashboards/dashboard-*.json" &>/dev/null; then
        log_info "Moving dashboard JSON files"
        mv "${GRAFANA_PROVISIONING_DIR}/dashboards/dashboard-*.json" "${GRAFANA_PROVISIONING_DIR}/dashboards/"
    fi

    # Restart Grafana to apply changes
    restart_service grafana-server

    log_success "Grafana provisioning completed"
}

# Check Grafana status
check_grafana() {
    log_info "Checking Grafana status"

    # Check if Grafana is installed
    if ! dpkg -l | grep -q grafana; then
        log_error "Grafana is not installed"
        return 1
    fi

    # Check if Grafana service is running
    if ! systemctl is-active --quiet grafana-server; then
        log_error "Grafana service is not running"
        return 1
    fi

    # Check if Grafana is responding
    if ! curl -s "http://localhost:${GRAFANA_PORT}/api/health" &>/dev/null; then
        log_error "Grafana is not responding"
        return 1
    fi

    log_success "Grafana is installed and running"
    return 0
}

# Uninstall Grafana
uninstall_grafana() {
    log_info "Uninstalling Grafana"

    # Stop and disable service
    if systemctl is-active --quiet grafana-server; then
        systemctl stop grafana-server
    fi
    if systemctl is-enabled --quiet grafana-server; then
        systemctl disable grafana-server
    fi

    # Remove package
    apt-get remove -y grafana

    # Ask if data and configuration should be removed
    read -p "Remove Grafana data and configuration? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Remove data and configuration
        apt-get purge -y grafana
        rm -rf "${GRAFANA_CONFIG_DIR}"
    fi

    # Remove repository
    rm -f /etc/apt/sources.list.d/grafana.list
    rm -f /etc/apt/keyrings/grafana.gpg

    log_success "Grafana uninstalled"
}