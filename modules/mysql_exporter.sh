#!/bin/bash
#
# MySQL Exporter installation functions
#

# Default values
MYSQL_EXPORTER_VERSION="0.16.0"
MYSQL_EXPORTER_USER="prometheus"
MYSQL_EXPORTER_GROUP="prometheus"
MYSQL_EXPORTER_PORT="9104"
MYSQL_EXPORTER_CONFIG_FILE="/etc/.mysqld_exporter.cnf"
# We'll handle the password differently now - no default password

# Variable to store the MySQL exporter password for display_status
MYSQL_EXPORTER_PASSWORD_USED=""

# Generate a random password
generate_random_password() {
    local length=${1:-16}
    < /dev/urandom tr -dc A-Za-z0-9 | head -c${length}
}

# Install MySQL Exporter
install_mysql_exporter() {
    local version=${1:-$MYSQL_EXPORTER_VERSION}
    local mysql_user=${2:-"mysqld_exporter"}
    local mysql_password=${3:-""}

    # If no password provided, prompt for one or generate a random one
    if [[ -z "$mysql_password" ]]; then
        # Prompt for password
        read -p "Enter MySQL exporter password (leave empty to generate random password): " -r user_password

        if [[ -z "$user_password" ]]; then
            # Generate random password if user didn't provide one
            mysql_password=$(generate_random_password)
            log_info "Generated random password for MySQL exporter"
        else
            mysql_password="$user_password"
        fi
    fi

    # Store the password for display_status
    MYSQL_EXPORTER_PASSWORD_USED="$mysql_password"

    log_info "Installing MySQL Exporter version ${version}"

    # Check if MySQL is installed
    if ! command_exists mysql; then
        log_warning "MySQL is not installed. Please install MySQL before installing MySQL Exporter."
        return 1
    fi

    # Ensure prometheus user exists
    create_user "${MYSQL_EXPORTER_USER}"

    # Download and extract MySQL Exporter
    cd "${TEMP_DIR}"
    local mysql_exporter_archive="mysqld_exporter-${version}.linux-${ARCH}.tar.gz"
    local mysql_exporter_url="https://github.com/prometheus/mysqld_exporter/releases/download/v${version}/${mysql_exporter_archive}"

    download_file "${mysql_exporter_url}" "${mysql_exporter_archive}"
    extract_archive "${mysql_exporter_archive}" "${TEMP_DIR}"

    # Move binary to the correct location
    local extracted_dir="mysqld_exporter-${version}.linux-${ARCH}"
    cd "${extracted_dir}"

    log_info "Moving MySQL Exporter binary to /usr/local/bin"
    mv mysqld_exporter /usr/local/bin/
    chown "${MYSQL_EXPORTER_USER}:${MYSQL_EXPORTER_GROUP}" /usr/local/bin/mysqld_exporter
    chmod 755 /usr/local/bin/mysqld_exporter

    # Create MySQL user for exporter if password is provided
    if [[ -n "${mysql_password}" ]]; then
        create_mysql_user "${mysql_user}" "${mysql_password}"
    else
        log_warning "MySQL password not provided. Skipping MySQL user creation."
        log_warning "You will need to create a MySQL user manually and configure the exporter."
    fi

    # Create configuration file
    create_mysql_exporter_config "${mysql_user}" "${mysql_password}"

    # Create systemd service
    create_mysql_exporter_service

    # Reload systemd, enable and start MySQL Exporter
    reload_systemd
    enable_service "mysql_exporter"
    start_service "mysql_exporter"

    # Check if MySQL Exporter is running
    check_service_status "mysql_exporter"

    # Add to Prometheus configuration
    if command_exists prometheus; then
        add_scrape_config "mysql" "localhost:${MYSQL_EXPORTER_PORT}"
    else
        log_warning "Prometheus is not installed. You will need to configure it manually to scrape MySQL Exporter."
    fi

    log_success "MySQL Exporter ${version} installed successfully"
}

# Create MySQL user for exporter
create_mysql_user() {
    local mysql_user=$1
    local mysql_password=$2

    log_info "Creating MySQL user for exporter: ${mysql_user}"

    # Check if user already exists
    if mysql -u root -e "SELECT User FROM mysql.user WHERE User='${mysql_user}'" | grep -q "${mysql_user}"; then
        log_warning "MySQL user ${mysql_user} already exists. Skipping user creation."
        return 0
    fi

    # Create MySQL user and grant permissions
    mysql -u root -e "CREATE USER '${mysql_user}'@'localhost' IDENTIFIED BY '${mysql_password}';"
    mysql -u root -e "GRANT PROCESS, REPLICATION CLIENT, SLAVE MONITOR, SELECT ON *.* TO '${mysql_user}'@'localhost';"
    mysql -u root -e "FLUSH PRIVILEGES;"

    log_success "MySQL user created: ${mysql_user}"
}

# Create MySQL Exporter configuration file
create_mysql_exporter_config() {
    local mysql_user=$1
    local mysql_password=$2

    log_info "Creating MySQL Exporter configuration file"

    # Create configuration file
    cat > "${MYSQL_EXPORTER_CONFIG_FILE}" << EOF
[client]
user=${mysql_user}
password=${mysql_password}
EOF

    # Set permissions
    chown root:"${MYSQL_EXPORTER_GROUP}" "${MYSQL_EXPORTER_CONFIG_FILE}"
    chmod 640 "${MYSQL_EXPORTER_CONFIG_FILE}"

    log_success "MySQL Exporter configuration file created"
}

# Create MySQL Exporter systemd service
create_mysql_exporter_service() {
    local service_content="[Unit]
Description=Prometheus MySQL Exporter
Wants=network-online.target
After=network.target

[Service]
Type=simple
User=${MYSQL_EXPORTER_USER}
Group=${MYSQL_EXPORTER_GROUP}
ExecStart=/usr/local/bin/mysqld_exporter \\
    --config.my-cnf=${MYSQL_EXPORTER_CONFIG_FILE} \\
    --collect.auto_increment.columns \\
    --collect.binlog_size \\
    --collect.global_status \\
    --collect.global_variables \\
    --collect.info_schema.innodb_metrics \\
    --collect.info_schema.processlist \\
    --collect.info_schema.query_response_time \\
    --collect.info_schema.tables \\
    --collect.info_schema.tablestats \\
    --collect.info_schema.userstats \\
    --collect.perf_schema.eventswaits \\
    --collect.perf_schema.file_events \\
    --collect.perf_schema.indexiowaits \\
    --collect.perf_schema.tableiowaits \\
    --collect.perf_schema.tablelocks \\
    --collect.slave_status \\
    --web.listen-address=0.0.0.0:${MYSQL_EXPORTER_PORT}
Restart=always

[Install]
WantedBy=multi-user.target"

    create_systemd_service "mysql_exporter" "${service_content}"
}

# Check MySQL Exporter status
check_mysql_exporter() {
    log_info "Checking MySQL Exporter status"

    # Check if MySQL Exporter is installed
    if [[ ! -f "/usr/local/bin/mysqld_exporter" ]]; then
        log_error "MySQL Exporter is not installed"
        return 1
    fi

    # Check if MySQL Exporter service is running
    if ! systemctl is-active --quiet mysql_exporter; then
        log_error "MySQL Exporter service is not running"
        return 1
    fi

    # Check if MySQL Exporter is responding
    if ! curl -s "http://localhost:${MYSQL_EXPORTER_PORT}/metrics" &>/dev/null; then
        log_error "MySQL Exporter is not responding"
        return 1
    fi

    log_success "MySQL Exporter is installed and running"
    return 0
}

# Uninstall MySQL Exporter
uninstall_mysql_exporter() {
    log_info "Uninstalling MySQL Exporter"

    # Stop and disable service
    if systemctl is-active --quiet mysql_exporter; then
        systemctl stop mysql_exporter
    fi
    if systemctl is-enabled --quiet mysql_exporter; then
        systemctl disable mysql_exporter
    fi

    # Remove service file
    if [[ -f "/etc/systemd/system/mysql_exporter.service" ]]; then
        rm -f "/etc/systemd/system/mysql_exporter.service"
        systemctl daemon-reload
    fi

    # Remove binary
    if [[ -f "/usr/local/bin/mysqld_exporter" ]]; then
        rm -f "/usr/local/bin/mysqld_exporter"
    fi

    # Remove configuration file
    if [[ -f "${MYSQL_EXPORTER_CONFIG_FILE}" ]]; then
        rm -f "${MYSQL_EXPORTER_CONFIG_FILE}"
    fi

    # Ask if MySQL user should be removed
    read -p "Remove MySQL user 'mysqld_exporter'? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Remove MySQL user
        if command_exists mysql; then
            mysql -u root -e "DROP USER IF EXISTS 'mysqld_exporter'@'localhost';"
            mysql -u root -e "FLUSH PRIVILEGES;"
            log_success "MySQL user 'mysqld_exporter' removed"
        else
            log_warning "MySQL is not installed. Cannot remove user."
        fi
    fi

    # Remove from Prometheus configuration if Prometheus is installed
    if [[ -f "/etc/prometheus/prometheus.yml" ]]; then
        log_info "Removing MySQL Exporter from Prometheus configuration"
        sed -i '/job_name: .mysql./,+3d' /etc/prometheus/prometheus.yml

        # Restart Prometheus if it's running
        if systemctl is-active --quiet prometheus; then
            systemctl restart prometheus
        fi
    fi

    log_success "MySQL Exporter uninstalled"
}