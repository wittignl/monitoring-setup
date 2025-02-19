#!/bin/bash

# Installation Test Suite
# Tests the installation process of all monitoring components

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
    # Create test config directory if in development
    mkdir -p "$CONFIG_ROOT"/{prometheus,grafana,blackbox_exporter,mysql_exporter}
    mkdir -p "$CONFIG_ROOT/grafana/provisioning"
fi

# Source Multipass functions if needed
if [ "$USE_MULTIPASS" -eq 1 ]; then
    # Source the Multipass test environment script
    source "$SCRIPT_DIR/multipass_test_env.sh"
fi

# Service status check
check_service() {
    if [ "$USE_MULTIPASS" -eq 1 ]; then
        exec_in_vm "systemctl is-active --quiet $1"
    elif [ "$TEST_ENV" = "development" ]; then
        # Mock service check in development
        echo "Service $1 check simulated in development mode"
        return 0
    else
        systemctl is-active --quiet "$1"
    fi
}

# Port check
check_port() {
    if [ "$USE_MULTIPASS" -eq 1 ]; then
        exec_in_vm "nc -z -w 5 localhost $1"
    elif [ "$TEST_ENV" = "development" ]; then
        # Mock port check in development
        echo "Port $1 check simulated in development mode"
        return 0
    else
        nc -z -w 5 localhost "$1"
    fi
}

# Metric endpoint check
check_metrics() {
    if [ "$USE_MULTIPASS" -eq 1 ]; then
        exec_in_vm "curl -s --connect-timeout 5 'http://localhost:$1/metrics' | grep -q '^# HELP'"
    elif [ "$TEST_ENV" = "development" ]; then
        # Mock metrics check in development
        echo "Metrics endpoint $1 check simulated in development mode"
        return 0
    else
        curl -s --connect-timeout 5 "http://localhost:$1/metrics" | grep -q "^# HELP"
    fi
}

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

# Begin Tests
log "Starting Installation Tests" "$YELLOW"
echo "------------------------"

# Prometheus Tests
run_test "Prometheus Service Status" "check_service prometheus"
run_test "Prometheus Port (9095)" "check_port 9095"
run_test "Prometheus Metrics Endpoint" "check_metrics 9095"
run_test "Prometheus Config File" "check_file $CONFIG_ROOT/prometheus/prometheus.yml"

# Grafana Tests
run_test "Grafana Service Status" "check_service grafana-server"
run_test "Grafana Port (3000)" "check_port 3000"
run_test "Grafana Config Directory" "check_directory $CONFIG_ROOT/grafana"
run_test "Grafana Provisioning" "check_directory $CONFIG_ROOT/grafana/provisioning"

# Node Exporter Tests
run_test "Node Exporter Service Status" "check_service node_exporter"
run_test "Node Exporter Port (9100)" "check_port 9100"
run_test "Node Exporter Metrics" "check_metrics 9100"

# MySQL Exporter Tests
run_test "MySQL Exporter Service Status" "check_service mysql_exporter"
run_test "MySQL Exporter Port (9104)" "check_port 9104"
run_test "MySQL Exporter Metrics" "check_metrics 9104"

# Blackbox Exporter Tests
run_test "Blackbox Exporter Service Status" "check_service blackbox_exporter"
run_test "Blackbox Exporter Port (9115)" "check_port 9115"
run_test "Blackbox Exporter Config" "check_file $CONFIG_ROOT/blackbox_exporter/blackbox.yml"

# PM2 Exporter Tests
run_test "PM2 Exporter Service Status" "check_service pm2_exporter"
run_test "PM2 Exporter Port (9116)" "check_port 9116"

# Duplicati Exporter Tests
run_test "Duplicati Exporter Service Status" "check_service duplicati_exporter"
run_test "Duplicati Exporter Port (9118)" "check_port 9118"

# Summary
echo "------------------------"
log "Test Summary:" "$YELLOW"
log "Passed: $PASSED" "$GREEN"
log "Failed: $FAILED" "$RED"
log "Total: $TOTAL" "$NC"

# Exit with status
[ $FAILED -eq 0 ]
