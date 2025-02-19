#!/bin/bash

# Grafana Installation Module
# Version: 1.0.0
# Installs and configures Grafana for monitoring stack

install_grafana_ubuntu() {
    log "Installing Grafana on Ubuntu"

    # Add Grafana GPG key
    wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key

    # Add Grafana repository
    echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | \
        tee /etc/apt/sources.list.d/grafana.list

    # Update package list and install Grafana
    apt-get update
    apt-get install -y "grafana=${GRAFANA_VERSION}"

    log_success "Grafana package installed successfully"
}

install_grafana_centos() {
    log "Installing Grafana on CentOS"

    # Add Grafana repository
    cat > /etc/yum.repos.d/grafana.repo << EOF
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

    # Install Grafana package
    yum install -y "grafana-${GRAFANA_VERSION}"

    log_success "Grafana package installed successfully"
}

configure_grafana() {
    log "Configuring Grafana"

    # Create required directories
    mkdir -p /etc/grafana/provisioning/{datasources,dashboards,notifiers}

    # Set permissions
    chown -R "${GRAFANA_USER}:${GRAFANA_USER}" /etc/grafana/provisioning

    # Basic Grafana configuration
    cat > /etc/grafana/grafana.ini << EOF
[paths]
data = /var/lib/grafana
logs = /var/log/grafana
plugins = /var/lib/grafana/plugins

[server]
protocol = http
http_port = 3000

[security]
admin_user = admin

[users]
allow_sign_up = false

[auth.anonymous]
enabled = false

[dashboards]
versions_to_keep = 20

[unified_alerting]
enabled = true
evaluation_timeout = 30s
execute_alerts = true

[alerting]
enabled = false
notification_timeout = 30s

[smtp]
enabled = false

[metrics]
enabled = true
EOF

    # Configure Prometheus datasource
    cat > /etc/grafana/provisioning/datasources/prometheus.yaml << EOF
apiVersion: 1

deleteDatasources:
  - name: Prometheus
    orgId: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    orgId: 1
    url: http://localhost:9095
    isDefault: true
    version: 1
    editable: false
EOF

    # Copy notifier configuration
    cp -r "$(dirname "$0")/../config/grafana/provisioning/notifiers/"* /etc/grafana/provisioning/notifiers/
    chown -R "${GRAFANA_USER}:${GRAFANA_USER}" /etc/grafana/provisioning/notifiers

    # Configure dashboard provisioning
    cat > /etc/grafana/provisioning/dashboards/default.yaml << EOF
apiVersion: 1

providers:
  - name: 'Default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: true
    editable: false
    options:
      path: /etc/grafana/dashboards
EOF

    # Create required directories
    mkdir -p /etc/grafana/dashboards
    mkdir -p /etc/grafana/alerting

    # Copy dashboards and alert rules
    cp "$(dirname "$0")/../config/grafana/provisioning/dashboards/"*.json /etc/grafana/dashboards/
    cp "$(dirname "$0")/../config/grafana/provisioning/alerting/alert-rules.json" /etc/grafana/alerting/

    # Set permissions
    chown -R "${GRAFANA_USER}:${GRAFANA_USER}" /etc/grafana/dashboards
    chown -R "${GRAFANA_USER}:${GRAFANA_USER}" /etc/grafana/alerting

    log_success "Grafana configuration completed"
}

configure_mattermost() {
    log "Configuring Mattermost integration"

    if [ -n "${MATTERMOST_WEBHOOK_URL}" ]; then
        # Create environment file
        cat > /etc/grafana/grafana.env << EOF
MATTERMOST_WEBHOOK_URL=${MATTERMOST_WEBHOOK_URL}
EOF
        chown "${GRAFANA_USER}:${GRAFANA_USER}" /etc/grafana/grafana.env
        chmod 600 /etc/grafana/grafana.env

        # Update systemd service to use environment file
        mkdir -p /etc/systemd/system/grafana-server.service.d
        cat > /etc/systemd/system/grafana-server.service.d/override.conf << EOF
[Service]
EnvironmentFile=/etc/grafana/grafana.env
EOF

        log_success "Mattermost webhook configured"
    else
        log_warning "Skipping Mattermost configuration (webhook URL not provided)"
    fi
}

setup_grafana_service() {
    log "Setting up Grafana service"

    # Enable and start Grafana service
    systemctl daemon-reload
    systemctl enable grafana-server
    systemctl start grafana-server

    # Wait for service to start
    sleep 5

    if systemctl is-active --quiet grafana-server; then
        log_success "Grafana service started successfully"
    else
        log_error "Failed to start Grafana service"
        exit 1
    fi
}

install_grafana() {
    log "Starting Grafana installation"

    case $OS in
        "Ubuntu")
            install_grafana_ubuntu
            ;;
        "CentOS Linux")
            install_grafana_centos
            ;;
        *)
            log_error "Unsupported operating system for Grafana installation: $OS"
            exit 1
            ;;
    esac

    configure_grafana
    configure_mattermost
    setup_grafana_service

    log_success "Grafana installation completed"
}
