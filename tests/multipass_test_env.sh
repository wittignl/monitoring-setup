#!/bin/bash

# Multipass test environment management script

# Configuration
VM_NAME="monitoring-test"
VM_CPU="2"
VM_MEMORY="2G"
VM_DISK="10G"
UBUNTU_IMAGE="22.04"

# Debug mode
DEBUG=${DEBUG:-0}

# Debug logging function
debug_log() {
    if [ "$DEBUG" -eq 1 ]; then
        echo "[DEBUG] $1" >&2
    fi
}

# Function to check if Multipass is installed
check_multipass() {
    if ! command -v multipass &> /dev/null; then
        echo "Error: Multipass is not installed"
        echo "Please install Multipass first: https://multipass.run"
        exit 1
    fi
}

# Function to create test VM
create_test_vm() {
    echo "Creating test VM: $VM_NAME"
    multipass launch "$UBUNTU_IMAGE" \
                    --name "$VM_NAME" \
                    --cpus "$VM_CPU" \
                    --memory "$VM_MEMORY" \
                    --disk "$VM_DISK"
}

# Function to install required packages
install_packages() {
    echo "Installing required packages..."
    multipass exec "$VM_NAME" -- sudo bash -c '
        apt-get update -y
        apt-get install -y apt-transport-https software-properties-common wget curl netcat python3 python3-yaml jq
    '
}

# Function to destroy test VM
destroy_test_vm() {
    echo "Destroying test VM: $VM_NAME"
    multipass delete "$VM_NAME" --purge
}

# Function to check if VM exists
check_vm_exists() {
    multipass list | grep -q "$VM_NAME"
    return $?
}

# Function to copy project files to VM
copy_project_files() {
    local project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    echo "Copying project files to VM..."

    # Create a temporary tar file
    local temp_tar=$(mktemp)
    tar -czf "$temp_tar" -C "$project_root" src test_config

    # Copy and extract in VM
    multipass exec "$VM_NAME" -- mkdir -p /home/ubuntu/src /home/ubuntu/test_config
    multipass copy-files "$temp_tar" "$VM_NAME:/home/ubuntu/temp.tar"
    multipass exec "$VM_NAME" -- bash -c 'cd /home/ubuntu && tar xzf temp.tar && rm temp.tar'

    # Cleanup local temp file
    rm "$temp_tar"
}

# Function to execute command in VM
exec_in_vm() {
    multipass exec "$VM_NAME" -- sudo bash -c "$1"
}

# Function to wait for package manager
wait_for_package_manager() {
    echo "Waiting for package manager to be ready..."
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if ! multipass exec "$VM_NAME" -- sudo fuser /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; then
            echo "Package manager is ready"
            return 0
        fi
        echo "Waiting for package manager (attempt $attempt/$max_attempts)..."
        sleep 5
        attempt=$((attempt + 1))
    done

    echo "Error: Package manager is still locked"
    return 1
}

# Function to verify VM readiness
verify_vm_ready() {
    echo "Verifying VM readiness..."
    local max_attempts=30
    local attempt=1

    # Wait for VM to respond to basic commands
    while [ $attempt -le $max_attempts ]; do
        debug_log "Checking VM responsiveness (attempt $attempt/$max_attempts)"

        if multipass exec "$VM_NAME" -- true >/dev/null 2>&1; then
            echo "VM is responsive"
            return 0
        fi

        echo "Waiting for VM to become responsive (attempt $attempt/$max_attempts)..."
        sleep 5
        attempt=$((attempt + 1))
    done

    echo "Error: VM is not responding to commands"
    multipass info "$VM_NAME"
    return 1
}

# Function to setup test environment
setup_test_env() {
    check_multipass

    if check_vm_exists; then
        echo "Test VM already exists, destroying it first..."
        destroy_test_vm
    fi

    create_test_vm
    verify_vm_ready || { echo "Failed to verify VM readiness"; return 1; }
    install_packages || { echo "Failed to install packages"; return 1; }
    copy_project_files
}

# Function to cleanup test environment
cleanup_test_env() {
    if check_vm_exists; then
        destroy_test_vm
    fi
}

# Main execution
case "${1:-}" in
    "setup")
        setup_test_env
        ;;
    "cleanup")
        cleanup_test_env
        ;;
    *)
        echo "Usage: $0 {setup|cleanup}"
        exit 1
        ;;
esac
