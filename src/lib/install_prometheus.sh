#!/bin/bash

# Prometheus Installation Module
# Version: 1.0.0
# Installs and configures Prometheus for monitoring stack

install_prometheus() {
    log "Starting Prometheus installation"

    # Create directories
    mkdir -p /etc/prometheus
    mkdir -p /var/lib/prometheus

    # Download Prometheus
    local arch="amd64"
    local prometheus_archive="prometheus-${PROMETHEUS_VERSION}.linux-${arch}"
    local download_url="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${prometheus_archive}.tar.gz"

    log "Downloading Prometheus ${PROMETHEUS_VERSION}"
    wget -q -O /tmp/prometheus.tar.gz "${download_url}"

    # Extract Prometheus
    tar xzf /tmp/prometheus.tar.gz -C /tmp/

    # Copy binaries
    cp "/tmp/${prometheus_archive}/prometheus" /usr/local/bin/
    cp "/tmp/${prometheus_archive}/promtool" /usr/local/bin/

    # Copy console libraries and templates
    cp -r "/tmp/${prometheus_archive}/consoles" /etc/prometheus/
    cp -r "/tmp/${prometheus_archive}/console_libraries" /etc/prometheus/

    # Clean up
    rm -rf /tmp/prometheus.tar.gz "/tmp/${prometheus_archive}"

    # Set permissions
    chown -R "${PROMETHEUS_USER}:${PROMETHEUS_USER}" /etc/prometheus
    chown -R "${PROMETHEUS_USER}:${PROMETHEUS_USER}" /var/lib/prometheus
    chmod 755 /usr/local/bin/prometheus
    chmod 755 /usr/local/bin/promtool

    log_success "Prometheus binaries installed"
}

configure_prometheus() {
    log "Configuring Prometheus"

    # Copy configuration from source
    cp "$(dirname "$0")/../config/prometheus/prometheus.yml" /etc/prometheus/

    # Create rules directory
    mkdir -p /etc/prometheus/rules
    chown -R "${PROMETHEUS_USER}:${PROMETHEUS_USER}" /etc/prometheus/rules
    chown -R "${PROMETHEUS_USER}:${PROMETHEUS_USER}" /etc/prometheus/prometheus.yml

    log_success "Prometheus configuration completed"
}

setup_prometheus_service() {
    log "Setting up Prometheus service"

    # Create systemd service file
    cat > /etc/systemd/system/prometheus.service << EOF
[Unit]
Description=Prometheus
Documentation=https://prometheus.io/docs/introduction/overview/
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=${PROMETHEUS_USER}
Group=${PROMETHEUS_USER}
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=:9095 \
  --web.enable-lifecycle \
  --storage.tsdb.retention.time=15d

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and start service
    systemctl daemon-reload
    systemctl enable prometheus
    systemctl start prometheus

    # Wait for service to start
    sleep 5

    if systemctl is-active --quiet prometheus; then
        log_success "Prometheus service started successfully"
    else
        log_error "Failed to start Prometheus service"
        exit 1
    fi
}

install_prometheus_stack() {
    log "Starting Prometheus stack installation"

    install_prometheus
    configure_prometheus
    setup_prometheus_service

    log_success "Prometheus stack installation completed"
}
