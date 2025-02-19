#!/bin/bash

# Setup script for test environment
# Creates necessary configuration files with sample content

# Set test environment root
TEST_ROOT="./test_config"

# Create directory structure
mkdir -p "$TEST_ROOT"/{prometheus,grafana,blackbox_exporter,mysql_exporter,node_exporter,pm2_exporter,duplicati_exporter}
mkdir -p "$TEST_ROOT/grafana/provisioning"/{datasources,dashboards,alerting,notifiers}
mkdir -p "$TEST_ROOT/prometheus/rules"

# Prometheus configuration
cat > "$TEST_ROOT/prometheus/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF

# Prometheus Alert Manager configuration
cat > "$TEST_ROOT/prometheus/alertmanager.yml" << 'EOF'
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'mattermost'

receivers:
  - name: 'mattermost'
    webhook_configs:
      - url: 'http://localhost:8065/hooks/xxx'
EOF

# Grafana configuration
cat > "$TEST_ROOT/grafana/grafana.ini" << 'EOF'
[server]
http_port = 3000

[security]
admin_user = admin
admin_password = admin
EOF

# Alert rules
cat > "$TEST_ROOT/grafana/provisioning/alerting/alert-rules.json" << 'EOF'
{
  "groups": [
    {
      "name": "System Alerts",
      "rules": [
        {
          "name": "High CPU Usage",
          "query": "avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) > 0.8",
          "duration": "5m",
          "labels": {
            "severity": "warning"
          }
        }
      ]
    }
  ]
}
EOF

# Mattermost configuration
cat > "$TEST_ROOT/grafana/provisioning/notifiers/mattermost.yml" << 'EOF'
apiVersion: 1
notifiers:
  - name: Mattermost
    type: mattermost
    uid: mattermost1
    settings:
      url: http://localhost:8065/hooks/xxx
EOF

# Blackbox Exporter configuration
cat > "$TEST_ROOT/blackbox_exporter/blackbox.yml" << 'EOF'
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_status_codes: [200]
      method: GET
EOF

# Service files
for service in node mysql blackbox pm2 duplicati; do
    service_name="$(tr '[:lower:]' '[:upper:]' <<< ${service:0:1})${service:1}"
    cat > "$TEST_ROOT/${service}_exporter/${service}_exporter.service" << EOL
[Unit]
Description=${service_name} Exporter
After=network.target

[Service]
Type=simple
User=${service}_exporter
ExecStart=/usr/local/bin/${service}_exporter

[Install]
WantedBy=multi-user.target
EOL
done

echo "Test environment setup completed"
