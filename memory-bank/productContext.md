# Product Context: Monitoring Setup

## Project Overview

This project provides a modular Bash script-based solution for installing and configuring a complete monitoring stack on Ubuntu servers. The stack consists of Prometheus (for metrics collection and storage) and Grafana (for visualization and alerting), along with various exporters that collect metrics from different services.

## Purpose

The purpose of this monitoring setup is to provide a simple, modular, and easily maintainable way to deploy a comprehensive monitoring solution for servers and applications. It follows the KISS (Keep It Simple, Stupid) principle while offering flexibility and extensibility.

## Core Components

### 1. Prometheus
- Time-series database for storing metrics
- Query language for analyzing metrics
- Alerting capabilities
- Default port: 9095
- Configuration directory: `/etc/prometheus`
- Data directory: `/var/lib/prometheus`

### 2. Grafana
- Visualization platform for metrics
- Dashboard creation and management
- Alerting and notification system
- Default port: 3000
- Configuration directory: `/etc/grafana`
- Default credentials: admin/admin

### 3. Exporters
The project supports multiple exporters to collect metrics from various sources:

| Exporter | Purpose | Default Port |
|----------|---------|--------------|
| Node Exporter | System metrics (CPU, memory, disk, network) | 9100 |
| Blackbox Exporter | HTTP, HTTPS, TCP, ICMP probes | 9115 |
| MySQL Exporter | MySQL server metrics | 9104 |
| PM2 Exporter | PM2 process metrics | 9116 |

## Project Structure

```
monitoring-setup/
├── install.sh                  # Main installation script
├── modules/                    # Modular installation scripts
│   ├── common.sh               # Common functions
│   ├── prometheus.sh           # Prometheus installation
│   ├── grafana.sh              # Grafana installation
│   ├── node_exporter.sh        # Node Exporter installation
│   ├── blackbox_exporter.sh    # Blackbox Exporter installation
│   ├── mysql_exporter.sh       # MySQL Exporter installation
│   └── pm2_exporter.sh         # PM2 Exporter installation
└── provisioning/               # Grafana provisioning files
    ├── alerting/               # Alert rules and notification channels
    │   ├── alert-rules.json    # Predefined alert rules
    │   ├── contact-points.json # Contact points configuration
    │   └── policies.json       # Notification policies
    ├── dashboards/             # Predefined dashboards
    │   ├── dashboard-node.json # Node metrics dashboard
    │   ├── dashboard-mysql.json # MySQL metrics dashboard
    │   ├── dashboard-alerts.json # Alerts dashboard
    │   ├── dashboard-duplicati.json # Duplicati backup dashboard
    │   └── default.yml         # Dashboard provider configuration
    └── datasources/            # Data source configurations
        └── prometheus.yml      # Prometheus data source
```

## Installation Process

The installation process is designed to be flexible and modular:

1. The main `install.sh` script handles command-line arguments and orchestrates the installation.
2. Each component has its own module script in the `modules/` directory.
3. The script can install all components or selected ones based on command-line arguments.
4. Grafana is provisioned with predefined dashboards, data sources, and alert rules.

## Configuration Options

The installation can be customized through:

1. Command-line arguments to select which components to install
2. Environment variables to configure specific aspects (ports, passwords, etc.)
3. Pre-configured provisioning files for Grafana

## Memory Bank Structure

This Memory Bank contains the following core files:

1. **productContext.md** (this file): Provides an overview of the project, its components, and structure.
2. **activeContext.md**: Tracks the current session context and ongoing work.
3. **progress.md**: Tracks progress on tasks and features.
4. **decisionLog.md**: Records important architectural and design decisions.

## Technical Considerations

1. **Security**:
   - Default MySQL Exporter password should be changed in production
   - Services bind to localhost by default for security
   - Firewall configuration is required for remote access

2. **Scalability**:
   - The modular design allows for adding new exporters
   - File-based provisioning enables easy configuration management
   - Reusable functions for file copying and environment variable processing

3. **Maintenance**:
   - Each component is isolated in its own module
   - Clear separation of concerns makes updates easier
   - Systemd services enable easy management and automatic restarts

## Future Considerations

Potential areas for enhancement:

1. Adding support for additional exporters (e.g., Redis, PostgreSQL)
2. Implementing high availability for Prometheus and Grafana
3. Adding automated backup and restore functionality
4. Supporting additional Linux distributions beyond Ubuntu
5. Implementing a web-based configuration interface