# Monitoring Installation Script

A modular Bash script for installing Grafana and Prometheus on Ubuntu servers.

## Features

- Modular design with clear separation of components
- Support for multiple exporters (Node, Blackbox, MySQL, PM2)
- Grafana provisioning with dashboards, alerts, and notifiers
- Easy to maintain and extend
- Follows the KISS principle

## Prerequisites

- Ubuntu 20.04 or 22.04
- Root or sudo access
- Internet connection
- At least 1GB of free disk space

## Quick Start

### Direct Installation

You can install the monitoring stack directly using curl:

```bash
curl -s https://raw.githubusercontent.com/brentdenboer/monitoring-setup/main/install.sh | sudo bash -s -- --all
```

### Manual Installation

1. Clone the repository:

```bash
git clone https://github.com/user/repo.git
cd repo
```

2. Make the script executable:

```bash
chmod +x install.sh
```

3. Run the installation script:

```bash
sudo ./install.sh --all
```

## Usage

```
Usage: ./install.sh [options]

Options:
  --help                  Display this help message
  --prometheus            Install Prometheus
  --grafana               Install Grafana
  --node-exporter         Install Node Exporter
  --blackbox-exporter     Install Blackbox Exporter
  --mysql-exporter        Install MySQL Exporter
  --pm2-exporter          Install PM2 Exporter
  --all                   Install all components
  --skip-provisioning     Skip Grafana provisioning
  --version VERSION       Specify version for components
```

### Examples

Install only Prometheus and Grafana:

```bash
sudo ./install.sh --prometheus --grafana
```

Install Node Exporter with a specific version:

```bash
sudo ./install.sh --node-exporter --version 1.7.0
```

Install all components but skip Grafana provisioning:

```bash
sudo ./install.sh --all --skip-provisioning
```

## Components

### Prometheus

- Default port: 9095
- Configuration directory: `/etc/prometheus`
- Data directory: `/var/lib/prometheus`

### Grafana

- Default port: 3000
- Configuration directory: `/etc/grafana`
- Default credentials: admin/admin

### Node Exporter

- Default port: 9100
- Metrics: System metrics (CPU, memory, disk, network)

### Blackbox Exporter

- Default port: 9115
- Metrics: HTTP, HTTPS, TCP, ICMP probes

### MySQL Exporter

- Default port: 9104
- Metrics: MySQL server metrics
- Configuration file: `/etc/.mysqld_exporter.cnf`

> **Security Note:** By default, the MySQL Exporter uses a predefined password if `MYSQL_EXPORTER_PASSWORD` is not set. For production environments, it's strongly recommended to set a custom password using the environment variable.

### PM2 Exporter

- Default port: 9116
- Metrics: PM2 process metrics

## Grafana Provisioning

The script automatically provisions Grafana with:

- Prometheus datasource
- Node Exporter dashboard
- MySQL dashboard
- Alert rules
- Mattermost notification channel

## Configuration

### Environment Variables

You can configure the installation by setting environment variables before running the script:

```bash
# Set MySQL exporter password (recommended for production)
export MYSQL_EXPORTER_PASSWORD="your_secure_password"

# Set Mattermost webhook URL for notifications
export MATTERMOST_WEBHOOK_URL="https://mattermost.example.com/hooks/your-webhook-id"

# Run the installation script
sudo -E ./install.sh --all
```

> **Note:** The `-E` flag with sudo preserves environment variables when running the script.

If you're using the direct installation method with curl, you can set environment variables inline:

```bash
MYSQL_EXPORTER_PASSWORD="your_secure_password" curl -s https://raw.githubusercontent.com/brentdenboer/monitoring-setup/main/install.sh | sudo -E bash -s -- --all
```

#### Available Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MYSQL_EXPORTER_PASSWORD` | Password for MySQL exporter user | `exporter_password` |
| `MATTERMOST_WEBHOOK_URL` | Webhook URL for Mattermost notifications | None |
| `PROMETHEUS_PORT` | Port for Prometheus server | `9095` |
| `GRAFANA_PORT` | Port for Grafana server | `3000` |
| `NODE_EXPORTER_PORT` | Port for Node Exporter | `9100` |
| `BLACKBOX_EXPORTER_PORT` | Port for Blackbox Exporter | `9115` |
| `MYSQL_EXPORTER_PORT` | Port for MySQL Exporter | `9104` |
| `PM2_EXPORTER_PORT` | Port for PM2 Exporter | `9116` |

### Prometheus Configuration

The Prometheus configuration file is located at `/etc/prometheus/prometheus.yml`. You can modify this file to add additional scrape targets or change the configuration.

### Grafana Configuration

The Grafana configuration file is located at `/etc/grafana/grafana.ini`. You can modify this file to change the Grafana configuration.

## Firewall Configuration

By default, all services bind to localhost. If you want to access them remotely, you need to:

1. Configure the services to bind to a public interface
2. Configure your firewall to allow access to the ports

Example for UFW:

```bash
sudo ufw allow 9095/tcp  # Prometheus
sudo ufw allow 3000/tcp  # Grafana
```

## Troubleshooting

### Service Status

Check the status of a service:

```bash
sudo systemctl status prometheus
sudo systemctl status grafana-server
sudo systemctl status node_exporter
```

### Logs

View service logs:

```bash
sudo journalctl -u prometheus
sudo journalctl -u grafana-server
sudo journalctl -u node_exporter
```

### Common Issues

- **Port conflicts**: If a port is already in use, the service will fail to start. Check the logs for details.
- **Permission issues**: Ensure the service user has the necessary permissions.
- **Configuration errors**: Check the configuration files for syntax errors.

## Uninstallation

The script does not provide an uninstallation option, but you can manually uninstall the components:

```bash
# Stop and disable services
sudo systemctl stop prometheus grafana-server node_exporter blackbox_exporter mysql_exporter
sudo systemctl disable prometheus grafana-server node_exporter blackbox_exporter mysql_exporter

# Remove packages
sudo apt-get remove --purge grafana

# Remove binaries and configuration
sudo rm -rf /etc/prometheus /var/lib/prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
sudo rm -rf /etc/grafana
sudo rm -rf /usr/local/bin/node_exporter /usr/local/bin/blackbox_exporter /usr/local/bin/mysqld_exporter
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.