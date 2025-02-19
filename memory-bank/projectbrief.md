# Project Brief: Modular Installation & Update Tool for Monitoring

## Overview
This project provides a fully modular, re-runnable tool designed for traditional Linux servers (Ubuntu and older CentOS distributions) that installs, configures, and maintains a local monitoring stack consisting of:
- Grafana for visualization and alerting
- Prometheus for metrics collection
- Various exporters for system and service monitoring

## Core Requirements

### 1. Installation Capabilities
- Automated installation of Grafana, Prometheus, and exporters
- Support for both Ubuntu and CentOS distributions
- Package manager-based installation with fallback options
- Idempotent execution for safe re-runs

### 2. Configuration Management
- Grafana provisioning (datasources, dashboards, alerts)
- Prometheus configuration for scraping targets
- Exporter setup and configuration
- Service management via systemd

### 3. Monitoring Components
Based on the provided dashboards and configuration:
- Node monitoring (CPU, Memory, Disk, Network)
- MySQL monitoring
- SSL certificate monitoring
- Process monitoring (PM2)
- Alert management

### 4. Dashboard Templates
Pre-configured dashboards for:
- System metrics (dashboard-node.json)
- MySQL metrics (dashboard-mysql.json)
- Alert overview (dashboard-alerts.json)

### 5. Alert Rules
Comprehensive alerting for:
- Disk usage
- System load
- Memory utilization
- MySQL performance
- Process status
- SSL certificate expiration
- Service availability

## Project Structure
```
monitoring-setup/
├── src/
│   ├── main.sh             # Main orchestration script
│   ├── config/             # Configuration templates
│   │   ├── grafana/        # Grafana provisioning
│   │   ├── prometheus/     # Prometheus configuration
│   │   └── exporters/      # Exporter configurations
│   └── lib/                # Installation modules
```

## Success Criteria
1. Successful installation and configuration of all components via GitHub URL
2. Proper visualization through pre-configured dashboards
3. Functional alerting system
4. Ability to safely update configurations
5. Reliable service management
6. Verified functionality in Multipass test environment
