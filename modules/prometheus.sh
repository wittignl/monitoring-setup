#!/bin/bash
#
# Prometheus installation functions
#

# Default values
PROMETHEUS_VERSION="3.1.0"
PROMETHEUS_USER="prometheus"
PROMETHEUS_GROUP="prometheus"
PROMETHEUS_PORT="9095"
PROMETHEUS_CONFIG_DIR="/etc/prometheus"
PROMETHEUS_DATA_DIR="/var/lib/prometheus"
PROMETHEUS_BIN_DIR="/usr/local/bin"

# Install Prometheus
install_prometheus() {
    local version=${1:-$PROMETHEUS_VERSION}

    log_info "Installing Prometheus version ${version}"

    # Create prometheus user
    create_user "${PROMETHEUS_USER}"

    # Create directories
    create_directory "${PROMETHEUS_CONFIG_DIR}" "${PROMETHEUS_USER}" "${PROMETHEUS_GROUP}" "0755"
    create_directory "${PROMETHEUS_DATA_DIR}" "${PROMETHEUS_USER}" "${PROMETHEUS_GROUP}" "0755"

    # Download and extract Prometheus
    cd "${TEMP_DIR}"
    local prometheus_archive="prometheus-${version}.linux-${ARCH}.tar.gz"
    local prometheus_url="https://github.com/prometheus/prometheus/releases/download/v${version}/${prometheus_archive}"

    download_file "${prometheus_url}" "${prometheus_archive}"
    extract_archive "${prometheus_archive}" "${TEMP_DIR}"

    # Move files to the correct locations
    local extracted_dir="prometheus-${version}.linux-${ARCH}"
    cd "${extracted_dir}"

    # Move binaries
    log_info "Moving Prometheus binaries to ${PROMETHEUS_BIN_DIR}"
    mv prometheus promtool "${PROMETHEUS_BIN_DIR}/"
    chown "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${PROMETHEUS_BIN_DIR}/prometheus" "${PROMETHEUS_BIN_DIR}/promtool"
    chmod 755 "${PROMETHEUS_BIN_DIR}/prometheus" "${PROMETHEUS_BIN_DIR}/promtool"

    # Move configuration files
    log_info "Moving Prometheus configuration files to ${PROMETHEUS_CONFIG_DIR}"
    if [[ -d "consoles" ]]; then
        cp -r consoles "${PROMETHEUS_CONFIG_DIR}/"
    fi
    if [[ -d "console_libraries" ]]; then
        cp -r console_libraries "${PROMETHEUS_CONFIG_DIR}/"
    fi

    # Create or update prometheus.yml
    if [[ ! -f "${PROMETHEUS_CONFIG_DIR}/prometheus.yml" ]]; then
        cp prometheus.yml "${PROMETHEUS_CONFIG_DIR}/"
    else
        log_info "Prometheus configuration file already exists, not overwriting"
    fi

    # Set ownership and permissions
    chown -R "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${PROMETHEUS_CONFIG_DIR}"

    # Create systemd service
    create_prometheus_service

    # Reload systemd, enable and start Prometheus
    reload_systemd
    enable_service "prometheus"
    start_service "prometheus"

    # Check if Prometheus is running
    check_service_status "prometheus"

    log_success "Prometheus ${version} installed successfully"
}

# Create Prometheus systemd service
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
    --web.listen-address=0.0.0.0:${PROMETHEUS_PORT}
SyslogIdentifier=prometheus
Restart=always

[Install]
WantedBy=multi-user.target"

    create_systemd_service "prometheus" "${service_content}"
}

# Configure Prometheus
configure_prometheus() {
    log_info "Configuring Prometheus"

    # Backup existing configuration
    backup_config_file "${PROMETHEUS_CONFIG_DIR}/prometheus.yml"

    # Create basic configuration if it doesn't exist
    if [[ ! -f "${PROMETHEUS_CONFIG_DIR}/prometheus.yml" ]]; then
        cat > "${PROMETHEUS_CONFIG_DIR}/prometheus.yml" << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:${PROMETHEUS_PORT}']
EOF
        chown "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${PROMETHEUS_CONFIG_DIR}/prometheus.yml"
        chmod 644 "${PROMETHEUS_CONFIG_DIR}/prometheus.yml"
        log_success "Created basic Prometheus configuration"
    fi
}

# Add scrape config for an exporter
add_scrape_config() {
    local job_name=$1
    local target=$2
    local config_file="${PROMETHEUS_CONFIG_DIR}/prometheus.yml"
    local scrape_interval=${3:-15s}
    local metrics_path=${4:-/metrics}
    local scheme=${5:-http}

    log_info "Adding scrape config for ${job_name} to Prometheus"

    # Check if job already exists
    if grep -q "job_name: '${job_name}'" "${config_file}"; then
        log_warning "Scrape config for ${job_name} already exists, skipping"
        return 0
    fi

    # Create scrape config block with additional parameters
    local scrape_block="  - job_name: '${job_name}'
    scrape_interval: ${scrape_interval}
    scheme: ${scheme}
    metrics_path: ${metrics_path}
    static_configs:
      - targets: ['${target}']"

    # Use optimized YAML block addition
    add_scrape_config_to_prometheus "${config_file}" "${scrape_block}"

    # Restart Prometheus to apply changes
    restart_service "prometheus"

    log_success "Added scrape config for ${job_name} to Prometheus"
}

# Optimized function to add scrape config to prometheus.yml
add_scrape_config_to_prometheus() {
    local config_file=$1
    local scrape_block=$2

    # Backup the file
    backup_config_file "${config_file}"

    # Create a temporary file for the output
    local temp_file="${config_file}.tmp"

    # Create a temporary file for the scrape block
    local block_file=$(mktemp)
    echo "${scrape_block}" > "${block_file}"

    # Check if scrape_configs section exists
    if grep -q "^scrape_configs:" "${config_file}"; then
        # Add to existing scrape_configs section using a simpler approach
        awk -v block_file="${block_file}" '
        BEGIN {
            found = 0;
            printed = 0;
            # Read the block file content
            while ((getline line < block_file) > 0) {
                if (block == "") {
                    block = line;
                } else {
                    block = block "\n" line;
                }
            }
            close(block_file);
        }
        /^scrape_configs:/ {
            print $0;
            found = 1;
            next;
        }
        found == 1 && /^[a-z]/ && !/^  - / {
            if (printed == 0) {
                print block;
                printed = 1;
            }
            found = 0;
        }
        { print $0 }
        END {
            if (found == 1 && printed == 0) {
                print block;
            }
        }
        ' "${config_file}" > "${temp_file}"
    else
        # Add new scrape_configs section
        cat "${config_file}" > "${temp_file}"
        echo -e "\nscrape_configs:\n${scrape_block}" >> "${temp_file}"
    fi

    # Clean up the temporary block file
    rm -f "${block_file}"

    # Replace original file with temporary file
    mv "${temp_file}" "${config_file}"
    chown "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${config_file}"
    chmod 644 "${config_file}"

    log_success "Updated Prometheus configuration file"
}

# Remove a scrape config
remove_scrape_config() {
    local job_name=$1
    local config_file="${PROMETHEUS_CONFIG_DIR}/prometheus.yml"

    log_info "Removing scrape config for ${job_name} from Prometheus"

    # Check if job exists
    if ! grep -q "job_name: '${job_name}'" "${config_file}"; then
        log_warning "Scrape config for ${job_name} not found, nothing to remove"
        return 0
    fi

    # Backup the file
    backup_config_file "${config_file}"

    # Create a temporary file
    local temp_file="${config_file}.tmp"

    # Remove the job block
    awk -v job="job_name: '${job_name}'" '
    BEGIN { skip = 0; job_found = 0 }
    $0 ~ job { skip = 1; job_found = 1; next }
    skip == 1 && /^  - / { skip = 0 }
    skip == 0 { print $0 }
    END { if (job_found == 0) exit 1 }
    ' "${config_file}" > "${temp_file}"

    # Check if job was found and removed
    if [ $? -eq 0 ]; then
        mv "${temp_file}" "${config_file}"
        chown "${PROMETHEUS_USER}:${PROMETHEUS_GROUP}" "${config_file}"
        chmod 644 "${config_file}"

        # Restart Prometheus to apply changes
        restart_service "prometheus"

        log_success "Removed scrape config for ${job_name} from Prometheus"
    else
        rm "${temp_file}"
        log_error "Failed to remove scrape config for ${job_name}"
        return 1
    fi
}

# Check Prometheus status
check_prometheus() {
    log_info "Checking Prometheus status"

    # Check if Prometheus is installed
    if [[ ! -f "${PROMETHEUS_BIN_DIR}/prometheus" ]]; then
        log_error "Prometheus is not installed"
        return 1
    fi

    # Check if Prometheus service is running
    if ! systemctl is-active --quiet prometheus; then
        log_error "Prometheus service is not running"
        return 1
    fi

    # Check if Prometheus is responding
    if ! curl -s "http://localhost:${PROMETHEUS_PORT}/-/healthy" &>/dev/null; then
        log_error "Prometheus is not responding"
        return 1
    fi

    log_success "Prometheus is installed and running"
    return 0
}

# Uninstall Prometheus
uninstall_prometheus() {
    log_info "Uninstalling Prometheus"

    # Stop and disable service
    if systemctl is-active --quiet prometheus; then
        systemctl stop prometheus
    fi
    if systemctl is-enabled --quiet prometheus; then
        systemctl disable prometheus
    fi

    # Remove service file
    if [[ -f "/etc/systemd/system/prometheus.service" ]]; then
        rm -f "/etc/systemd/system/prometheus.service"
        systemctl daemon-reload
    fi

    # Remove binaries
    if [[ -f "${PROMETHEUS_BIN_DIR}/prometheus" ]]; then
        rm -f "${PROMETHEUS_BIN_DIR}/prometheus"
    fi
    if [[ -f "${PROMETHEUS_BIN_DIR}/promtool" ]]; then
        rm -f "${PROMETHEUS_BIN_DIR}/promtool"
    fi

    # Ask if data and configuration should be removed
    read -p "Remove Prometheus data and configuration? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Remove data and configuration
        if [[ -d "${PROMETHEUS_DATA_DIR}" ]]; then
            rm -rf "${PROMETHEUS_DATA_DIR}"
        fi
        if [[ -d "${PROMETHEUS_CONFIG_DIR}" ]]; then
            rm -rf "${PROMETHEUS_CONFIG_DIR}"
        fi
    fi

    log_success "Prometheus uninstalled"
}