#!/bin/bash

# Test Runner Script
# Executes all test suites and provides a comprehensive report

# Script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Create temp directory and set cleanup
TEMP_DIR=$(mktemp -d)

# Environment variables
USE_MULTIPASS=0

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
    if [ "$USE_MULTIPASS" -eq 1 ]; then
        log "Cleaning up Multipass environment..." "$BLUE"
        "$SCRIPT_DIR/multipass_test_env.sh" cleanup
    fi
}

trap cleanup EXIT

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test result counters
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_TESTS=0

# Logging function
log() {
    echo -e "${2:-$NC}$1${NC}"
}

# Debug mode flag
DEBUG=${DEBUG:-0}

# Debug logging function
debug_log() {
    if [ "$DEBUG" -eq 1 ]; then
        echo -e "${BLUE}[DEBUG] $1${NC}" >&2
    fi
}

# Function to run a test suite and capture results
run_test_suite() {
    local suite_name=$1
    local script_path="$SCRIPT_DIR/$2"
    local output_file="$TEMP_DIR/${2##*/}.out"

    log "\n📋 Running $suite_name..." "$BLUE"
    echo "================================"

    # Check if test script exists and is executable
    if [ ! -x "$script_path" ]; then
        log "Error: Test script $script_path not found or not executable" "$RED"
        return 1
    fi

    debug_log "Executing: $script_path"
    debug_log "Output file: $output_file"

    # Run the test suite and capture output
    if "$script_path" > "$output_file" 2>&1; then
        local suite_status="PASSED"
        local status_color="$GREEN"
    else
        local suite_status="FAILED"
        local status_color="$RED"
    fi

    # Display test output if in debug mode or if test failed
    if [ "$DEBUG" -eq 1 ] || [ "$suite_status" = "FAILED" ]; then
        echo -e "\nTest Output:"
        cat "$output_file"
        echo
    fi

    # Extract results from the test suite output
    local passed=$(grep -o "Passed: [0-9]*" "$output_file" | awk '{sum += $2} END {print sum}')
    local failed=$(grep -o "Failed: [0-9]*" "$output_file" | awk '{sum += $2} END {print sum}')
    local total=$(grep -o "Total: [0-9]*" "$output_file" | awk '{sum += $2} END {print sum}')

    # Update total counters
    ((TOTAL_PASSED += passed))
    ((TOTAL_FAILED += failed))
    ((TOTAL_TESTS += total))

    # Print suite summary
    echo "--------------------------------"
    log "Suite Status: $suite_status" "$status_color"
    log "Tests Passed: $passed" "$GREEN"
    log "Tests Failed: $failed" "$RED"
    log "Total Tests: $total" "$NC"
    echo "================================"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -m, --multipass    Run tests in Multipass VM"
    echo "  -h, --help        Show this help message"
}

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -m|--multipass)
            USE_MULTIPASS=1
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Print header
log "\n🔍 Starting Monitoring Stack Test Suite" "$BLUE"
echo "================================"
date
echo "--------------------------------"

# Setup test environment if using Multipass
if [ "$USE_MULTIPASS" -eq 1 ]; then
    log "\n🖥️  Setting up Multipass test environment..." "$BLUE"
    if ! "$SCRIPT_DIR/multipass_test_env.sh" setup; then
        log "Failed to setup Multipass environment" "$RED"
        exit 1
    fi
fi

# Run each test suite
run_test_suite "Installation Tests" "installation_test.sh"
run_test_suite "Configuration Tests" "config_validation_test.sh"
run_test_suite "Alert Tests" "alert_test.sh"

# Print final summary
log "\n📊 Final Test Summary" "$BLUE"
echo "================================"
log "Total Tests Passed: $TOTAL_PASSED" "$GREEN"
log "Total Tests Failed: $TOTAL_FAILED" "$RED"
log "Total Tests Run: $TOTAL_TESTS" "$NC"
echo "--------------------------------"
date
echo "================================"

# Determine exit status
if [ $TOTAL_FAILED -eq 0 ]; then
    log "\n✅ All test suites passed successfully!" "$GREEN"
    exit 0
else
    log "\n❌ Some tests failed. Please check the test output above for details." "$RED"
    exit 1
fi
