#!/bin/bash
#
# MySQL Exporter installation functions
#

MYSQL_EXPORTER_VERSION="0.16.0"
MYSQL_EXPORTER_USER="prometheus"
MYSQL_EXPORTER_GROUP="prometheus"
MYSQL_EXPORTER_PORT="9104"
MYSQL_EXPORTER_CONFIG_FILE="/etc/.mysqld_exporter.cnf"


install_mysql_exporter() {
    local version=${1:-$MYSQL_EXPORTER_VERSION}
    local mysql_user=${2:-"monitoring"}
    local mysql_password=${3}

    if [[ -z "${mysql_password}" ]]; then
        handle_error "MySQL exporter password must be provided as the third argument to install_mysql_exporter"
    fi

    log_info "Installing MySQL Exporter version ${version}"

    if ! command_exists mysql; then
        log_warning "MySQL is not installed. Please install MySQL before installing MySQL Exporter."
        return 1
    fi

    create_user "${MYSQL_EXPORTER_USER}"

    cd "${TEMP_DIR}"
    local mysql_exporter_archive="mysqld_exporter-${version}.linux-${ARCH}.tar.gz"
    local mysql_exporter_url="https://github.com/prometheus/mysqld_exporter/releases/download/v${version}/${mysql_exporter_archive}"

    download_file "${mysql_exporter_url}" "${mysql_exporter_archive}"
    extract_archive "${mysql_exporter_archive}" "${TEMP_DIR}"

    local extracted_dir="mysqld_exporter-${version}.linux-${ARCH}"
    cd "${extracted_dir}"

    log_info "Moving MySQL Exporter binary to /usr/local/bin"
    mv mysqld_exporter /usr/local/bin/
    chown "${MYSQL_EXPORTER_USER}:${MYSQL_EXPORTER_GROUP}" /usr/local/bin/mysqld_exporter
    chmod 755 /usr/local/bin/mysqld_exporter

    log_warning "MySQL user creation is now manual. Ensure user '${mysql_user}' exists with necessary grants."

    create_mysql_exporter_config "${mysql_user}" "${mysql_password}"

    create_mysql_exporter_service

    reload_systemd
    enable_service "mysql_exporter"
    start_service "mysql_exporter"

    check_service_status "mysql_exporter"

    if command_exists prometheus; then
        add_scrape_config "mysql" "localhost:${MYSQL_EXPORTER_PORT}"
    else
        log_warning "Prometheus is not installed. You will need to configure it manually to scrape MySQL Exporter."
    fi

    log_success "MySQL Exporter ${version} installed successfully"
}

create_mysql_exporter_config() {
    local mysql_user=$1
    local mysql_password=$2

    if [[ ! -f "${MYSQL_EXPORTER_CONFIG_FILE}" ]]; then
        log_info "Creating MySQL Exporter configuration file: ${MYSQL_EXPORTER_CONFIG_FILE}"
        cat > "${MYSQL_EXPORTER_CONFIG_FILE}" << EOF
[client]
user=${mysql_user}
password=${mysql_password}
EOF
        chown root:"${MYSQL_EXPORTER_GROUP}" "${MYSQL_EXPORTER_CONFIG_FILE}"
        chmod 640 "${MYSQL_EXPORTER_CONFIG_FILE}"
        log_success "MySQL Exporter configuration file created"
    else
        log_info "MySQL Exporter configuration file ${MYSQL_EXPORTER_CONFIG_FILE} already exists, skipping creation."
        # Ensure permissions are still correct
        chown root:"${MYSQL_EXPORTER_GROUP}" "${MYSQL_EXPORTER_CONFIG_FILE}"
        chmod 640 "${MYSQL_EXPORTER_CONFIG_FILE}"
    fi
}

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
    --web.listen-address=127.0.0.1:${MYSQL_EXPORTER_PORT}
Restart=always

[Install]
WantedBy=multi-user.target"

    create_systemd_service "mysql_exporter" "${service_content}"
}

check_mysql_exporter() {
    log_info "Checking MySQL Exporter status"

    if [[ ! -f "/usr/local/bin/mysqld_exporter" ]]; then
        log_error "MySQL Exporter is not installed"
        return 1
    fi

    if ! systemctl is-active --quiet mysql_exporter; then
        log_error "MySQL Exporter service is not running"
        return 1
    fi

    if ! curl -s "http://localhost:${MYSQL_EXPORTER_PORT}/metrics" &>/dev/null; then
        log_error "MySQL Exporter is not responding"
        return 1
    fi

    log_success "MySQL Exporter is installed and running"
    return 0
}

uninstall_mysql_exporter() {
    log_info "Uninstalling MySQL Exporter"

    if systemctl is-active --quiet mysql_exporter; then
        systemctl stop mysql_exporter
    fi
    if systemctl is-enabled --quiet mysql_exporter; then
        systemctl disable mysql_exporter
    fi

    if [[ -f "/etc/systemd/system/mysql_exporter.service" ]]; then
        rm -f "/etc/systemd/system/mysql_exporter.service"
        systemctl daemon-reload
    fi

    if [[ -f "/usr/local/bin/mysqld_exporter" ]]; then
        rm -f "/usr/local/bin/mysqld_exporter"
    fi

    if [[ -f "${MYSQL_EXPORTER_CONFIG_FILE}" ]]; then
        rm -f "${MYSQL_EXPORTER_CONFIG_FILE}"
    fi

    log_info "MySQL user 'monitoring' (or the one specified during install) is not automatically removed. Please remove it manually if desired."

    if [[ -f "/etc/prometheus/prometheus.yml" ]]; then
        log_info "Removing MySQL Exporter from Prometheus configuration"
        sed -i '/job_name: .mysql./,+3d' /etc/prometheus/prometheus.yml

        if systemctl is-active --quiet prometheus; then
            systemctl restart prometheus
        fi
    fi

    log_success "MySQL Exporter uninstalled"
}