#!/bin/bash

# MySQL Exporter Installation Module
# Version: 1.0.0
# Installs and configures MySQL Exporter for MySQL metrics collection

install_mysql_exporter() {
    log "Starting MySQL Exporter installation"

    # Download MySQL Exporter
    local arch="amd64"
    local mysql_exporter_archive="mysqld_exporter-${MYSQL_EXPORTER_VERSION}.linux-${arch}"
    local download_url="https://github.com/prometheus/mysqld_exporter/releases/download/v${MYSQL_EXPORTER_VERSION}/${mysql_exporter_archive}.tar.gz"

    log "Downloading MySQL Exporter ${MYSQL_EXPORTER_VERSION}"
    wget -q -O /tmp/mysql_exporter.tar.gz "${download_url}"

    # Extract MySQL Exporter
    tar xzf /tmp/mysql_exporter.tar.gz -C /tmp/

    # Copy binary
    cp "/tmp/${mysql_exporter_archive}/mysqld_exporter" /usr/local/bin/

    # Clean up
    rm -rf /tmp/mysql_exporter.tar.gz "/tmp/${mysql_exporter_archive}"

    # Set permissions
    chmod 755 /usr/local/bin/mysqld_exporter
    chown "${MYSQL_EXPORTER_USER}:${MYSQL_EXPORTER_USER}" /usr/local/bin/mysqld_exporter

    log_success "MySQL Exporter binary installed"
}

configure_mysql_exporter() {
    log "Configuring MySQL Exporter"

    # Create config directory
    mkdir -p /etc/mysql_exporter

    # Create MySQL user and grant permissions
    mysql -e "
        CREATE USER IF NOT EXISTS 'mysqld_exporter'@'localhost' IDENTIFIED BY '${MYSQL_EXPORTER_PASSWORD}' WITH MAX_USER_CONNECTIONS 3;
        GRANT PROCESS, REPLICATION CLIENT, SLAVE MONITOR, SELECT ON *.* TO 'mysqld_exporter'@'localhost';
        FLUSH PRIVILEGES;
    " || {
        log_warning "Failed to create MySQL user. Please ensure MySQL is installed and running."
        log_warning "You may need to manually create the user with the following permissions:"
        log_warning "PROCESS, REPLICATION CLIENT, SELECT"
        return 0  # Continue installation despite warning
    }

    # Create credentials file
    cat > /etc/mysql_exporter/.my.cnf << EOF
[client]
user=mysqld_exporter
password=${MYSQL_EXPORTER_PASSWORD}
EOF

    # Set secure permissions for credentials
    chown "${MYSQL_EXPORTER_USER}:${MYSQL_EXPORTER_USER}" /etc/mysql_exporter/.my.cnf
    chmod 600 /etc/mysql_exporter/.my.cnf

    log_success "MySQL Exporter configuration completed"
}

setup_mysql_exporter_service() {
    log "Setting up MySQL Exporter service"

    # Create systemd service file
    cat > /etc/systemd/system/mysql_exporter.service << EOF
[Unit]
Description=MySQL Exporter
Documentation=https://github.com/prometheus/mysqld_exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=${MYSQL_EXPORTER_USER}
Group=${MYSQL_EXPORTER_USER}
Environment=DATA_SOURCE_NAME=\${DATA_SOURCE_NAME}
ExecStart=/usr/local/bin/mysqld_exporter \
  --config.my-cnf=/etc/mysql_exporter/.my.cnf \
  --collect.auto_increment.columns \
  --collect.binlog_size \
  --collect.global_status \
  --collect.global_variables \
  --collect.info_schema.innodb_metrics \
  --collect.info_schema.processlist \
  --collect.info_schema.query_response_time \
  --collect.info_schema.tables \
  --collect.info_schema.tablestats \
  --collect.info_schema.userstats \
  --collect.perf_schema.eventswaits \
  --collect.perf_schema.file_events \
  --collect.perf_schema.indexiowaits \
  --collect.perf_schema.tableiowaits \
  --collect.perf_schema.tablelocks \
  --collect.slave_status \
  --web.listen-address=:9104

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and start service
    systemctl daemon-reload
    systemctl enable mysql_exporter
    systemctl start mysql_exporter

    # Wait for service to start
    sleep 5

    if systemctl is-active --quiet mysql_exporter; then
        log_success "MySQL Exporter service started successfully"
    else
        log_error "Failed to start MySQL Exporter service"
        exit 1
    fi
}

install_mysql_exporter_stack() {
    log "Starting MySQL Exporter stack installation"

    install_mysql_exporter
    configure_mysql_exporter
    setup_mysql_exporter_service

    log_success "MySQL Exporter stack installation completed"
}
