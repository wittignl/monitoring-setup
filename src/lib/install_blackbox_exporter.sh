#!/bin/bash

# Blackbox Exporter Installation Module
# Version: 1.0.0
# Installs and configures Blackbox Exporter for endpoint and SSL monitoring

install_blackbox_exporter() {
    log "Starting Blackbox Exporter installation"

    # Download Blackbox Exporter
    local arch="amd64"
    local blackbox_exporter_archive="blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-${arch}"
    local download_url="https://github.com/prometheus/blackbox_exporter/releases/download/v${BLACKBOX_EXPORTER_VERSION}/${blackbox_exporter_archive}.tar.gz"

    log "Downloading Blackbox Exporter ${BLACKBOX_EXPORTER_VERSION}"
    wget -q -O /tmp/blackbox_exporter.tar.gz "${download_url}"

    # Extract Blackbox Exporter
    tar xzf /tmp/blackbox_exporter.tar.gz -C /tmp/

    # Copy binary
    cp "/tmp/${blackbox_exporter_archive}/blackbox_exporter" /usr/local/bin/

    # Clean up
    rm -rf /tmp/blackbox_exporter.tar.gz "/tmp/${blackbox_exporter_archive}"

    # Set permissions
    chmod 755 /usr/local/bin/blackbox_exporter
    chown "${BLACKBOX_EXPORTER_USER}:${BLACKBOX_EXPORTER_USER}" /usr/local/bin/blackbox_exporter

    log_success "Blackbox Exporter binary installed"
}

configure_blackbox_exporter() {
    log "Configuring Blackbox Exporter"

    # Create config directory
    mkdir -p /etc/blackbox_exporter

    # Move the default configuration file
    mv "/tmp/${blackbox_exporter_archive}/blackbox.yml" /etc/blackbox_exporter/

    # Set permissions
    chown -R "${BLACKBOX_EXPORTER_USER}:${BLACKBOX_EXPORTER_USER}" /etc/blackbox_exporter
    chmod 644 /etc/blackbox_exporter/blackbox.yml

    log_success "Blackbox Exporter configuration completed"
}

setup_blackbox_exporter_service() {
    log "Setting up Blackbox Exporter service"

    # Create systemd service file
    cat > /etc/systemd/system/blackbox_exporter.service << EOF
[Unit]
Description=Blackbox Exporter
Documentation=https://github.com/prometheus/blackbox_exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=${BLACKBOX_EXPORTER_USER}
Group=${BLACKBOX_EXPORTER_USER}
ExecStart=/usr/local/bin/blackbox_exporter \
  --config.file=/etc/blackbox_exporter/blackbox.yml \
  --web.listen-address=:9115

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and start service
    systemctl daemon-reload
    systemctl enable blackbox_exporter
    systemctl start blackbox_exporter

    # Wait for service to start
    sleep 5

    if systemctl is-active --quiet blackbox_exporter; then
        log_success "Blackbox Exporter service started successfully"
    else
        log_error "Failed to start Blackbox Exporter service"
        exit 1
    fi
}

install_blackbox_exporter_stack() {
    log "Starting Blackbox Exporter stack installation"

    install_blackbox_exporter
    configure_blackbox_exporter
    setup_blackbox_exporter_service

    log_success "Blackbox Exporter stack installation completed"
}
