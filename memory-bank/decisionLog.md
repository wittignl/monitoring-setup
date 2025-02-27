# Decision Log

This document tracks key architectural and design decisions made during the development of the monitoring setup project.

## Architectural Decisions

### AD-001: Modular Script Design
- **Date**: Prior to project analysis
- **Decision**: Implement the installation as modular bash scripts rather than a monolithic script
- **Context**: Need for maintainability and flexibility in installation options
- **Consequences**:
  - Positive: Easier maintenance, clear separation of concerns
  - Positive: Components can be installed independently
  - Positive: Easier to extend with new exporters
  - Negative: Slightly more complex initial setup with multiple files

### AD-002: Prometheus as the Core Metrics Store
- **Date**: Prior to project analysis
- **Decision**: Use Prometheus as the central metrics collection and storage system
- **Context**: Need for a reliable, scalable time-series database for metrics
- **Consequences**:
  - Positive: Industry-standard solution with wide adoption
  - Positive: Rich query language (PromQL)
  - Positive: Built-in alerting capabilities
  - Positive: Wide range of exporters available
  - Negative: Requires more resources than some lighter alternatives

### AD-003: Grafana for Visualization
- **Date**: Prior to project analysis
- **Decision**: Use Grafana for metrics visualization and dashboard management
- **Context**: Need for flexible, powerful visualization of metrics
- **Consequences**:
  - Positive: Industry-standard visualization platform
  - Positive: Rich dashboard capabilities
  - Positive: Support for multiple data sources
  - Positive: Built-in alerting and notification system
  - Negative: Adds another component to maintain

### AD-004: Systemd for Service Management
- **Date**: Prior to project analysis
- **Decision**: Use systemd for managing services
- **Context**: Need for reliable service management with automatic restarts
- **Consequences**:
  - Positive: Standard on modern Ubuntu systems
  - Positive: Reliable service management
  - Positive: Automatic restart on failure
  - Positive: Easy to check service status
  - Negative: Limited to systemd-based distributions

### AD-005: Direct Prometheus Configuration
- **Date**: 2025-02-27
- **Decision**: Remove JSON-based configuration for Prometheus scrape targets in favor of direct configuration
- **Context**: Simplify the configuration process by removing the extra layer of JSON configuration
- **Consequences**:
  - Positive: Simplified installation process
  - Positive: More direct and transparent configuration
  - Positive: Reduced complexity in the codebase
  - Negative: Less programmatic control over configuration

### AD-006: File-Based Grafana Provisioning
- **Date**: 2025-02-27
- **Decision**: Refactor Grafana provisioning to use existing files from the project's provisioning directory
- **Context**: Simplify the provisioning process by copying existing configuration files instead of generating them in-place
- **Consequences**:
  - Positive: More maintainable and consistent configuration
  - Positive: Easier to update and version control configuration files
  - Positive: Reduced code complexity with reusable file copying functions
  - Positive: Better error handling and reporting
  - Positive: Improved environment variable substitution
  - Negative: Requires maintaining separate configuration files in the project

### AD-007: Simplified Grafana Provisioning
- **Date**: 2025-02-27
- **Decision**: Replace multiple specialized provisioning functions with a single recursive directory copy operation
- **Context**: Further simplify the Grafana provisioning process by directly copying the entire provisioning directory structure
- **Consequences**:
  - Positive: Dramatically reduced code complexity (from ~100 lines to ~30 lines)
  - Positive: Improved maintainability with less code to manage
  - Positive: Future-proofing by automatically handling any new provisioning files or directories
  - Positive: More consistent file permissions and ownership
  - Positive: Preserved special handling for datasource references and paths
  - Negative: Slightly less granular error reporting for individual file operations

### AD-008: Enhanced MySQL Exporter Password Handling
- **Date**: 2025-02-27
- **Decision**: Implement interactive password prompting with fallback to random password generation for MySQL exporter
- **Context**: Improve security by removing hardcoded default password and provide better user experience
- **Consequences**:
  - Positive: Improved security by eliminating default hardcoded password
  - Positive: Better user experience with interactive password prompting
  - Positive: Automatic random password generation as a fallback
  - Positive: Password is displayed in the installation summary for reference
  - Positive: Global variable approach allows password to be accessed across functions
  - Negative: Slightly more complex installation process requiring user interaction

### AD-009: Interactive PM2 User Configuration
- **Date**: 2025-02-27
- **Decision**: Implement interactive user prompting for PM2 exporter
- **Context**: Improve user experience by allowing interactive selection of the PM2 user
- **Consequences**:
  - Positive: Better user experience with interactive user prompting
  - Positive: Maintains backward compatibility with command-line arguments
  - Positive: Sensible default (current user) when no input is provided
  - Negative: Slightly more complex installation process requiring user interaction

### AD-010: Fix for Prometheus Scrape Config String Handling
- **Date**: 2025-02-27
- **Decision**: Improve string quoting in awk command for Prometheus scrape config
- **Context**: Fix unterminated string error in the `add_scrape_config_to_prometheus()` function
- **Consequences**:
  - Positive: Resolved error when adding scrape configs to Prometheus
  - Positive: Improved reliability of the configuration process
  - Positive: Better handling of multi-line strings in awk commands
=======

## Future Decisions to Consider

### FD-001: High Availability Configuration
- **Context**: For production environments, high availability might be required
- **Options**:
  - Implement Prometheus federation
  - Set up Prometheus in HA mode with shared storage
  - Use Thanos or Cortex for distributed Prometheus

### FD-002: Additional Exporters Support
- **Context**: Different environments may require monitoring of additional services
- **Options**:
  - Add Redis Exporter
  - Add PostgreSQL Exporter
  - Add HAProxy Exporter
  - Add custom application exporters

### FD-003: Multi-Distribution Support
- **Context**: Support for distributions beyond Ubuntu
- **Options**:
  - Add support for Debian-based distributions
  - Add support for RHEL/CentOS/Fedora
  - Add support for SUSE/openSUSE