# Active Context

## Current Session: 2025-02-27

### Session Goals
- Understand the monitoring-setup project structure and functionality
- Create the Memory Bank with core files
- Document the project architecture and components

### Current Focus
- Initializing the Memory Bank with core documentation
- Creating a comprehensive project brief in productContext.md
- Setting up the structure for tracking progress and decisions

### Recent Activities
- Analyzed the project structure and files
- Examined the installation script (install.sh)
- Reviewed module scripts and provisioning configurations
- Created productContext.md with project overview
- Created activeContext.md (this file)

### Next Steps
- Create progress.md to track project progress
- Create decisionLog.md to document architectural decisions
- Identify potential architectural improvements or extensions
- Consider documentation for deployment scenarios and best practices

### Current Task: Remove Scrape Config Option
- Removed the `--use-scrape-config` and `--scrape-config FILE` options from install.sh
- Removed the `USE_SCRAPE_CONFIG` variable and related code in install.sh
- Removed the `skip_prometheus_config` parameter from exporter modules
- Removed the `add_scrape_configs_from_json` function from prometheus.sh
- Updated the decision log to reflect the architectural change
### Current Task: Simplify Grafana Provisioning Code
- Dramatically simplified the Grafana provisioning process by replacing multiple specialized functions with a single recursive directory copy
- Removed individual provisioning functions (`provision_datasources()`, `provision_dashboards()`, `provision_alert_rules()`, `import_dashboards()`)
- Implemented a more maintainable approach that directly copies the entire provisioning directory structure
- Preserved special handling for updating datasource references and paths
- Reduced code complexity while maintaining all functionality
- Improved future-proofing by automatically handling any new provisioning files or directories

### Current Task: Handle MySQL Password and PM2 User Environment Variables
- Modified MySQL exporter module to prompt for a password if not provided
- Implemented random password generation if user doesn't provide a password
- Added password logging in the display_status function
- Created a global variable to store the password for use in display_status
- Improved security by removing the default hardcoded password
- Modified PM2 exporter module to prompt for a user if not provided
- Used current user as default when no input is provided

### Current Task: Fix Prometheus Scrape Config Issue
- Fixed unterminated string error in the `add_scrape_config_to_prometheus()` function
- Corrected the string quoting in the awk command to properly handle multi-line strings
- Fixed both instances of the issue (in the main block and END block)

### Completed Task: Enhance Monitoring for New Server (192.168.42.4)
- Analyzed integration of Grafana monitoring components with newly added PM2 and Node Exporter metrics from IP 192.168.42.4
- Evaluated existing alert rules and dashboards for proper utilization of metrics from the new server
- Implemented dashboard modifications to distinguish between servers:
  - Updated panel titles and legends to include instance information
  - Added PM2 application-specific panels for memory usage and restarts
  - Modified template variables to properly capture instance information
- Enhanced alert rules to include instance information:
  - Added instance labels and annotations to all alert rules
  - Created a new PM2-specific alert rule for memory usage
  - Improved alert notifications with instance-specific context

### Completed Task: Optimize Monitoring Provisioning (Dashboards & Alerting)
- Analyzed existing Grafana dashboards and alerting rules for flexibility, aesthetics, and notification clarity.
- Implemented dashboard improvements:
  - Added `$job` and `$instance` variables to `dashboard-alerts.json`, `dashboard-mysql.json`, `dashboard-node.json`, `dashboard-duplicati.json`.
  - Replaced hardcoded `job` and `instance` values in queries with variables.
  - Corrected `repeat` variable mismatch in `dashboard-node.json` (`node` -> `instance`).
  - Enabled legends and added missing units for better clarity.
- Implemented alerting improvements:
  - Added `severity` label to all alert rules.
  - Added placeholder `runbook_url` annotation to all alert rules (subsequently removed per user request).
  - Added custom notification template to Mattermost contact point (`contact-points.json`) for improved formatting and context (runbook link logic subsequently removed per user request).
- Implemented `localhost` URL fix:
  - Modified `modules/grafana.sh` to configure `root_url` in `grafana.ini` based on `GRAFANA_EXTERNAL_URL` environment variable.