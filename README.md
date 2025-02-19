# Modular Monitoring Stack Setup

A comprehensive, modular tool for installing and configuring a complete monitoring stack on traditional Linux servers (Ubuntu and CentOS). This project provides automated setup of Grafana, Prometheus, and various exporters for system and service monitoring.

## Features

- **Automated Installation**: One-command setup from GitHub URL
- **Pre-configured Dashboards**: Ready-to-use dashboards for system metrics, MySQL, alerts, and backups
- **Comprehensive Monitoring**:
  - System metrics (CPU, Memory, Disk, Network)
  - MySQL database performance
  - SSL certificate monitoring
  - Process monitoring (PM2)
  - Backup status (Duplicati)
- **Alert Management**: Integrated alerting with Mattermost notifications
- **Idempotent Operations**: Safe re-runs for updates and modifications

## Requirements

### System Requirements
- Ubuntu or CentOS Linux distribution
- Systemd for service management
- Root access for installation

### Dependencies
- apt-transport-https/yum-utils
- software-properties-common
- wget
- systemd
- Node.js (for PM2 and Duplicati exporters)

### Port Requirements
- Grafana: 3000
- Prometheus: 9095
- Node Exporter: 9100
- MySQL Exporter: 9104
- PM2 Exporter: 9116
- Blackbox Exporter: 9115
- Duplicati Exporter: 9118

## Installation

### Quick Start
```bash
# Download and execute the installation script
curl -sSL https://github.com/user/repo/raw/main/src/main.sh | sudo bash
```

### Components Installed

#### Core Components
- **Grafana (v10.4.2)**
  - Visualization platform
  - Dashboard provisioning
  - Alert management
  - Mattermost integration

- **Prometheus (v3.1.0)**
  - Time-series database
  - Metrics collection
  - Query language (PromQL)
  - Rule-based alerting

#### Exporters
- **Node Exporter (v1.8.2)**
  - System metrics
  - Hardware statistics
  - Performance data

- **MySQL Exporter (v0.16.0)**
  - Database metrics
  - Query performance
  - Connection stats

- **Blackbox Exporter (v0.25.0)**
  - SSL certificate monitoring
  - HTTP endpoint checks
  - Network probing

- **PM2 Exporter**
  - Process monitoring
  - Application metrics
  - Resource usage

- **Duplicati Exporter**
  - Backup status monitoring
  - Duration tracking
  - Size metrics

## Configuration

### File Locations
```
/etc/
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   ├── dashboards/
│   │   ├── alerting/
│   │   └── notifiers/
│   └── grafana.env
├── prometheus/
│   ├── prometheus.yml
│   └── rules/
└── exporters/
    ├── node_exporter/
    ├── mysql_exporter/
    ├── blackbox_exporter/
    ├── pm2_exporter/
    └── duplicati_exporter/
```

### Service Management
All components are installed as systemd services:
```bash
# Check service status
systemctl status grafana-server
systemctl status prometheus
systemctl status node_exporter
systemctl status mysql_exporter
systemctl status blackbox_exporter
systemctl status pm2_exporter
systemctl status duplicati_exporter
```

### Dashboard Access
Access Grafana dashboards at `http://your-server:3000`:
- Default credentials: admin/admin
- Pre-configured dashboards:
  - System Metrics
  - MySQL Performance
  - Alert Overview
  - Duplicati Backup Status

## Testing

### Manual Testing with Multipass
```bash
# Create test environment
./tests/multipass_test_env.sh create

# Run installation
./tests/setup_test_env.sh

# Run test suite
./tests/run_tests.sh

# Clean up
./tests/multipass_test_env.sh delete
```

### Test Framework
- Installation validation
- Configuration verification
- Alert system testing
- Service status checks
- Metric collection validation

## Maintenance

### Updates
```bash
# Re-run installation script for updates
./src/main.sh
```

### Backup Recommendations
1. Configuration files
   - /etc/grafana/
   - /etc/prometheus/
   - /etc/exporters/

2. Dashboard exports
   ```bash
   # Export dashboards
   curl -X GET http://localhost:3000/api/dashboards/uid/[dashboard-uid]
   ```

3. Alert rules
   - Regular backup of /etc/prometheus/rules/

### Monitoring Guidelines
1. Regular checks:
   - Service status
   - Metric collection
   - Alert functionality
   - Backup status

2. Resource usage:
   - Monitor disk usage (15d retention)
   - Check service memory usage
   - Verify CPU utilization
   - Monitor network bandwidth

## Support

For issues and feature requests, please:
1. Check the troubleshooting guide
2. Verify service status and logs
3. Review configuration files
4. Submit detailed issue reports

## License

[Your License Here]
