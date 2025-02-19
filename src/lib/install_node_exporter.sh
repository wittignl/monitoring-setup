#!/bin/bash

# Node Exporter Installation Module
# Version: 1.0.0
# Installs and configures Node Exporter for system metrics collection

install_node_exporter() {
    log "Starting Node Exporter installation"

    # Download Node Exporter
    local arch="amd64"
    local node_exporter_archive="node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}"
    local download_url="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${node_exporter_archive}.tar.gz"

    log "Downloading Node Exporter ${NODE_EXPORTER_VERSION}"
    wget -q -O /tmp/node_exporter.tar.gz "${download_url}"

    # Extract Node Exporter
    tar xzf /tmp/node_exporter.tar.gz -C /tmp/

    # Copy binary
    cp "/tmp/${node_exporter_archive}/node_exporter" /usr/local/bin/

    # Clean up
    rm -rf /tmp/node_exporter.tar.gz "/tmp/${node_exporter_archive}"

    # Set permissions
    chmod 755 /usr/local/bin/node_exporter
    chown "${NODE_EXPORTER_USER}:${NODE_EXPORTER_USER}" /usr/local/bin/node_exporter

    log_success "Node Exporter binary installed"
}

setup_node_exporter_service() {
    log "Setting up Node Exporter service"

    # Create systemd service file
    cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
Documentation=https://github.com/prometheus/node_exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=${NODE_EXPORTER_USER}
Group=${NODE_EXPORTER_USER}
ExecStart=/usr/local/bin/node_exporter \
  --collector.systemd \
  --collector.processes \
  --collector.filesystem.mount-points-exclude="^/(dev|proc|sys|var/lib/docker/.+|var/lib/containers/.+)($|/)" \
  --collector.logind \
  --web.listen-address=:9100

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and start service
    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl start node_exporter

    # Wait for service to start
    sleep 5

    if systemctl is-active --quiet node_exporter; then
        log_success "Node Exporter service started successfully"
    else
        log_error "Failed to start Node Exporter service"
        exit 1
    fi
}

install_node_exporter_stack() {
    log "Starting Node Exporter stack installation"

    install_node_exporter
    setup_node_exporter_service

    log_success "Node Exporter stack installation completed"
}
