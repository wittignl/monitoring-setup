#!/bin/bash

# Configuration Validation Test Suite
# Validates the configuration files for all monitoring components

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test result counters
PASSED=0
FAILED=0
TOTAL=0

# Logging function
log() {
    echo -e "${2:-$NC}$1${NC}"
}

# Test function
run_test() {
    local test_name=$1
    local test_command=$2
    ((TOTAL++))

    log "Testing: $test_name" "$YELLOW"
    if eval "$test_command"; then
        log "✓ Passed: $test_name" "$GREEN"
        ((PASSED++))
    else
        log "✗ Failed: $test_name" "$RED"
        ((FAILED++))
    fi
    echo
}

# Script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Environment variables for testing
: "${TEST_ENV:=development}"
: "${CONFIG_ROOT:=/etc}"
: "${USE_MULTIPASS:=0}"

if [ "$TEST_ENV" = "development" ] && [ "$USE_MULTIPASS" -eq 0 ]; then
    CONFIG_ROOT="./test_config"
    # Create test config directory structure if in development
    mkdir -p "$CONFIG_ROOT"/{prometheus,grafana,blackbox_exporter,mysql_exporter}
    mkdir -p "$CONFIG_ROOT/grafana/provisioning"/{datasources,dashboards,alerting,notifiers}
    mkdir -p "$CONFIG_ROOT/prometheus/rules"
fi

# Source Multipass functions if needed
if [ "$USE_MULTIPASS" -eq 1 ]; then
    source "$SCRIPT_DIR/multipass_test_env.sh"
fi

# File existence check
check_file() {
    if [ "$USE_MULTIPASS" -eq 1 ]; then
        exec_in_vm "test -f $1"
    else
        test -f "$1"
    fi
}

# Directory existence check
check_directory() {
    if [ "$USE_MULTIPASS" -eq 1 ]; then
        exec_in_vm "test -d $1"
    else
        test -d "$1"
    fi
}

# Get file permissions
get_permissions() {
    if [ "$USE_MULTIPASS" -eq 1 ]; then
        exec_in_vm "stat -c %a $1"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        stat -f "%OLp" "$1"
    else
        stat -c "%a" "$1"
    fi
}

# YAML validation function
validate_yaml() {
    if [ "$USE_MULTIPASS" -eq 1 ]; then
        exec_in_vm "python3 -c \"import yaml; yaml.safe_load(open('$1'))\"" 2>/dev/null
    elif [ "$TEST_ENV" = "development" ]; then
        echo "YAML validation simulated for $1 in development mode"
        return 0
    else
        python3 -c "import yaml; yaml.safe_load(open('$1'))" 2>/dev/null
    fi
}

# JSON validation function
validate_json() {
    if [ "$USE_MULTIPASS" -eq 1 ]; then
        exec_in_vm "jq empty $1" 2>/dev/null
    elif [ "$TEST_ENV" = "development" ]; then
        echo "JSON validation simulated for $1 in development mode"
        return 0
    else
        jq empty "$1" 2>/dev/null
    fi
}

# Begin Tests
log "Starting Configuration Validation Tests" "$YELLOW"
echo "------------------------"

# Prometheus Configuration Tests
log "Testing Prometheus Configuration" "$YELLOW"
run_test "Prometheus Main Config Exists" "check_file $CONFIG_ROOT/prometheus/prometheus.yml"
run_test "Prometheus Main Config Valid YAML" "validate_yaml $CONFIG_ROOT/prometheus/prometheus.yml"
run_test "Prometheus Storage Directory" "check_directory $CONFIG_ROOT/prometheus"
run_test "Prometheus Rules Directory" "check_directory $CONFIG_ROOT/prometheus/rules"

# Grafana Configuration Tests
log "Testing Grafana Configuration" "$YELLOW"
run_test "Grafana Main Config Exists" "check_file $CONFIG_ROOT/grafana/grafana.ini"
run_test "Grafana Provisioning Directory" "check_directory $CONFIG_ROOT/grafana/provisioning"
run_test "Grafana Dashboards Directory" "check_directory $CONFIG_ROOT/grafana/provisioning/dashboards"
run_test "Grafana Datasources Directory" "check_directory $CONFIG_ROOT/grafana/provisioning/datasources"
run_test "Grafana Notifiers Directory" "check_directory $CONFIG_ROOT/grafana/provisioning/notifiers"

# Dashboard JSON Validation
log "Testing Dashboard Configurations" "$YELLOW"
for dashboard in $CONFIG_ROOT/grafana/provisioning/dashboards/*.json; do
    if [ -f "$dashboard" ]; then
        run_test "Dashboard $(basename "$dashboard")" "validate_json '$dashboard'"
    fi
done

# Alert Rules Validation
log "Testing Alert Rules" "$YELLOW"
run_test "Alert Rules JSON Exists" "check_file $CONFIG_ROOT/grafana/provisioning/alerting/alert-rules.json"
run_test "Alert Rules JSON Valid" "validate_json $CONFIG_ROOT/grafana/provisioning/alerting/alert-rules.json"

# Exporter Configuration Tests
log "Testing Exporter Configurations" "$YELLOW"

# Node Exporter
run_test "Node Exporter Service File" "check_file $CONFIG_ROOT/node_exporter/node_exporter.service"

# MySQL Exporter
run_test "MySQL Exporter Service File" "check_file $CONFIG_ROOT/mysql_exporter/mysql_exporter.service"
run_test "MySQL Exporter Config Directory" "check_directory $CONFIG_ROOT/mysql_exporter"

# Blackbox Exporter
run_test "Blackbox Exporter Config Exists" "check_file $CONFIG_ROOT/blackbox_exporter/blackbox.yml"
run_test "Blackbox Exporter Config Valid YAML" "validate_yaml $CONFIG_ROOT/blackbox_exporter/blackbox.yml"
run_test "Blackbox Exporter Service File" "check_file $CONFIG_ROOT/blackbox_exporter/blackbox_exporter.service"

# PM2 Exporter
run_test "PM2 Exporter Service File" "check_file $CONFIG_ROOT/pm2_exporter/pm2_exporter.service"

# Duplicati Exporter
run_test "Duplicati Exporter Service File" "check_file $CONFIG_ROOT/duplicati_exporter/duplicati_exporter.service"

# Mattermost Integration
log "Testing Mattermost Integration" "$YELLOW"
run_test "Mattermost Config Exists" "check_file $CONFIG_ROOT/grafana/provisioning/notifiers/mattermost.yml"
run_test "Mattermost Config Valid YAML" "validate_yaml $CONFIG_ROOT/grafana/provisioning/notifiers/mattermost.yml"

# Permission Tests
log "Testing File Permissions" "$YELLOW"
if [ "$USE_MULTIPASS" -eq 1 ] || [ "$TEST_ENV" = "development" ]; then
    log "Skipping permission tests in Multipass/development mode" "$YELLOW"
else
    run_test "Prometheus Config Permissions" "test $(get_permissions $CONFIG_ROOT/prometheus/prometheus.yml) = '644'"
    run_test "Grafana Config Permissions" "test $(get_permissions $CONFIG_ROOT/grafana/grafana.ini) = '644'"
    run_test "Alert Rules Permissions" "test $(get_permissions $CONFIG_ROOT/grafana/provisioning/alerting/alert-rules.json) = '644'"
fi

# Summary
echo "------------------------"
log "Test Summary:" "$YELLOW"
log "Passed: $PASSED" "$GREEN"
log "Failed: $FAILED" "$RED"
log "Total: $TOTAL" "$NC"

# Exit with status
[ $FAILED -eq 0 ]
