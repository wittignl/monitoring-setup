# Monitoring Stack Installation Script

A modular Bash script for installing and configuring a monitoring stack (Prometheus, Grafana, various exporters) on Ubuntu servers. This script simplifies the setup of essential monitoring components as systemd services.

## Overview

This script automates the installation and configuration of:

- **Prometheus:** Time-series database and monitoring system.
- **Grafana:** Visualization and analytics platform.
- **Node Exporter:** Exposes hardware and OS metrics.
- **Blackbox Exporter:** Enables probing of endpoints over HTTP, HTTPS, DNS, TCP, and ICMP.
- **MySQL Exporter:** Exposes metrics from a MySQL database server.
- **PM2 Exporter:** Exposes metrics from applications managed by PM2.

Components are installed as systemd services, typically running under dedicated users and binding to `localhost` by default for security.

## Prerequisites

- **Operating System:** Ubuntu (tested on 20.04, 22.04).
- **Access:** Root or `sudo` privileges are required to run the script.
- **Internet Connection:** Needed to download components and dependencies.
- **System Dependencies:** The script checks for and requires the following commands/packages. Most common ones are usually present.
  - `wget`
  - `tar`
  - `curl`
  - `git` (only if cloning manually)
  - `systemd` (systemctl, journalctl)
  - `runuser` (usually part of `util-linux`)
  - `mysql-client` (required _only_ if you need to perform the Manual MySQL Setup for the MySQL Exporter)
  - Standard utilities like `grep`, `sed`, `awk`, `useradd`, `groupadd`, `chmod`, `chown`, `mktemp`.
- **Application User for PM2 Exporter:** If installing the PM2 Exporter (`--pm2-exporter`), the user specified via the `--pm2-user=USERNAME` flag **must already exist** on the system.
- **NVM/Node.js/PM2 for PM2 User:** It is highly recommended that Node Version Manager (NVM), Node.js, and PM2 are pre-installed _for the application user_ specified with `--pm2-user`. While the script attempts to install these using `runuser` if they are missing for that user, pre-configuration ensures a smoother setup.

## Installation

1. **Clone the Repository (Optional but Recommended):**
   ```bash
   git clone https://github.com/brentdenboer/monitoring-setup.git
   cd monitoring-setup
   chmod +x install.sh
   ```
2. **Set Required Environment Variables:**
   - `MYSQL_PASSWORD`: **Required** if installing MySQL Exporter (`--mysql-exporter`). This password must match the one used during the Manual MySQL Setup.
   - `GRAFANA_ADMIN_PASSWORD`: **Required** if installing Grafana (`--grafana`). Sets the initial password for the Grafana `admin` user.
   - `GRAFANA_ROOT_URL`: Optional but recommended if installing Grafana. Sets the public-facing URL (e.g., `http://your-domain.com:3000`) used in alert notifications. Defaults to `http://127.0.0.1:3000/`.
   - `GRAFANA_ADMIN_USER`: Optional. Sets the initial Grafana admin username. Defaults to `admin`.

3. **Run the Script:** Execute the script with `sudo`. Use `-E` if passing environment variables. Select the components to install using flags.

   ```bash
   # Example: Install Prometheus, Grafana, Node Exporter, and PM2 Exporter
   # Assumes 'appuser' exists and has NVM/Node/PM2 installed.
   export MYSQL_PASSWORD="your_secure_mysql_password" # Needed only if --mysql-exporter is used
   export GRAFANA_ADMIN_PASSWORD="your_secure_grafana_admin_password"
   export GRAFANA_ROOT_URL="http://your-monitoring.example.com:3000"

   sudo -E ./install.sh \
     --prometheus \
     --grafana \
     --node-exporter \
     --pm2-exporter --pm2-user=appuser
   ```

### Command-Line Options

```
Usage: ./install.sh [options]

Options:
  --help                  Display help message
  --uninstall             Uninstall selected components instead of installing

  Installation/Uninstallation Targets:
  --prometheus            Select Prometheus
  --grafana               Select Grafana
  --node-exporter         Select Node Exporter
  --blackbox-exporter     Select Blackbox Exporter
  --mysql-exporter        Select MySQL Exporter
  --pm2-exporter          Select PM2 Exporter
  --all                   Select all components (requires all necessary env vars and user setup)

  Installation Options:
  --skip-provisioning     Skip Grafana provisioning (datasources, dashboards, alerts)
  --version VERSION       Specify version for components (applied to all selected, use with caution)
  --pm2-user USERNAME     **Required** when installing/uninstalling PM2 Exporter.
                          Specifies the existing application user whose PM2 instance will be monitored.
                          The script will run PM2-related commands as this user via 'runuser'.

  Environment Variables (Required for Installation):
  MYSQL_PASSWORD          Password for the MySQL Exporter user (must match manual setup).
  GRAFANA_ADMIN_PASSWORD  Password for the initial Grafana admin user.

  Environment Variables (Optional):
  GRAFANA_ADMIN_USER      Initial Grafana admin username (default: 'admin').
  GRAFANA_ROOT_URL        External root URL for Grafana (important for alerts).
```

### Manual MySQL Setup (Required for MySQL Exporter)

The script **does not** create the MySQL user for the exporter. You must create this user manually **before** running the installation with `--mysql-exporter`.

Connect to your MySQL server as root or another privileged user:

```sql
CREATE USER 'mysqld_exporter'@'localhost' IDENTIFIED BY 'your_secure_mysql_password' WITH MAX_USER_CONNECTIONS 3;
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'mysqld_exporter'@'localhost';
FLUSH PRIVILEGES;
```

**Important:** Replace `'your_secure_mysql_password'` with the **exact same password** you provide via the `MYSQL_PASSWORD` environment variable.

### PM2 User Setup (Required for PM2 Exporter)

- The `--pm2-user=USERNAME` flag is **mandatory** when using `--pm2-exporter`.
- The specified `USERNAME` **must exist** on the system before running the script.
- The script uses `runuser -u USERNAME -- <command>` to execute PM2-related actions (like installing the exporter module `pm2-prometheus-exporter`) as the application user.
- Ensure NVM, Node.js, and PM2 are installed and configured correctly for this user. The script attempts installation if missing, but pre-setup is more reliable.

## Configuration

- **Service Binding:** By default, all services (Prometheus, Grafana, Exporters) are configured to listen on `127.0.0.1` (localhost). To allow external access, you typically need to modify the service's configuration or systemd service file/override to listen on `0.0.0.0` or a specific IP address, and adjust firewall rules accordingly.
- **Prometheus:**
  - Main config: `/etc/prometheus/prometheus.yml`
  - Target discovery: Uses `file_sd_configs` pointing to files in `/etc/prometheus/targets/`. The script adds `*.yml` files here for installed exporters (e.g., `node_exporter.yml`, `pm2_exporter.yml`).
- **Grafana:**
  - Main config: `/etc/grafana/grafana.ini`
  - Overrides (e.g., admin password, root url): Set via environment variables in the systemd service override file (`/etc/systemd/system/grafana-server.service.d/override.conf`).
  - Provisioning: Configuration for datasources, dashboards, and alerting is placed in `/etc/grafana/provisioning/` (copied from the `provisioning/` directory of this repository during installation unless `--skip-provisioning` is used).
- **Exporters:**
  - **Node Exporter:** Configuration primarily via systemd service arguments (`/etc/systemd/system/node_exporter.service`).
  - **Blackbox Exporter:** Config file at `/etc/blackbox_exporter/config.yml`.
  - **MySQL Exporter:** Connection details (DSN) stored in `/etc/.mysqld_exporter.cnf` (using the `MYSQL_PASSWORD` env var).
  - **PM2 Exporter:** The `pm2-prometheus-exporter` module is installed globally for the `--pm2-user`. Configuration might reside within the user's PM2 environment (e.g., `~USERNAME/.pm2/`). The Prometheus target file is `/etc/prometheus/targets/pm2_exporter.yml`.

## Accessing Services

Default ports:

- **Prometheus:** `http://localhost:9090`
- **Grafana:** `http://localhost:3000`
- **Node Exporter:** `http://localhost:9100/metrics`
- **Blackbox Exporter:** `http://localhost:9115`
- **MySQL Exporter:** `http://localhost:9104/metrics`
- **PM2 Exporter:** `http://localhost:9209/metrics` (Verify port if customized)

Replace `localhost` with your server's IP address or domain name if you have configured services and firewalls for external access.

## Uninstallation

To uninstall components, use the `--uninstall` flag along with the component flags and any required arguments like `--pm2-user`.

```bash
# Example: Uninstall Grafana and PM2 Exporter for 'appuser'
sudo ./install.sh --uninstall --grafana --pm2-exporter --pm2-user=appuser
```

The uninstallation process attempts to:

- Stop and disable the systemd services.
- Remove systemd service files.
- Remove installed binaries and configuration directories (e.g., `/etc/prometheus`, `/etc/grafana`, exporter directories). May prompt for confirmation for data directories.
- Remove Prometheus target files from `/etc/prometheus/targets/`.
- Remove dedicated system users and groups created by the script (e.g., `prometheus`, `grafana`, `node_exporter`).
- For PM2 Exporter, it uses `runuser` to attempt removal of the `pm2-prometheus-exporter` module for the specified `--pm2-user`.

**What is NOT removed:**

- Manually installed dependencies (`mysql-client`, etc.).
- The application user specified via `--pm2-user`.
- NVM, Node.js, or PM2 installations within the application user's home directory.
- The manually created MySQL user (`mysqld_exporter`).

## Troubleshooting

- **Check Service Status:**
  ```bash
  sudo systemctl status <service_name>
  # e.g., prometheus, grafana-server, node_exporter, pm2_exporter@appuser.service
  ```
- **Check Service Logs:**
  ```bash
  sudo journalctl -u <service_name> -f
  # For PM2 exporter run as appuser: sudo journalctl -u pm2_exporter@appuser.service -f
  ```
- **PM2 Exporter Issues:**
  - Verify the `--pm2-user` exists and has PM2 running (`runuser -u USERNAME -- pm2 list`).
  - Check logs for the `pm2-prometheus-exporter` module within the user's PM2 logs (`runuser -u USERNAME -- pm2 logs pm2-prometheus-exporter`).
- **MySQL Exporter Issues:**
  - Ensure the `mysqld_exporter` MySQL user exists and the password in `/etc/.mysqld_exporter.cnf` matches the one set during manual creation.
  - Check MySQL grant privileges.
- **Configuration Validation:**
  - Prometheus: `sudo /usr/local/bin/prometheus/promtool check config /etc/prometheus/prometheus.yml`
- **Firewall:** Ensure ports are open if accessing remotely (`sudo ufw status`).
- **Permissions:** Check ownership and permissions on configuration files and directories.

## Contributing

Contributions, issues, and feature requests are welcome. Please feel free to submit a Pull Request or open an issue.

## License

This project is licensed under the MIT License.
