#!/bin/bash
#
# PM2 Exporter installation functions
#

# Default values
PM2_EXPORTER_PORT="9116"
PM2_EXPORTER_REPO="https://github.com/bblok11/pm2_exporter.git"
PM2_USER=""  # Default empty, will use current user if not specified

# Install PM2 Exporter
install_pm2_exporter() {
    local pm2_user=${1:-$PM2_USER}

    log_info "Installing PM2 Exporter"

    # Check if PM2 is installed
    if ! command_exists pm2; then
        log_warning "PM2 is not installed. Please install PM2 before installing PM2 Exporter."
        return 1
    fi

    # Check if Node.js and npm are installed
    if ! command_exists node || ! command_exists npm; then
        log_warning "Node.js or npm is not installed. Please install Node.js and npm before installing PM2 Exporter."
        return 1
    fi

    # If no PM2 user is specified, prompt for one
    if [[ -z "${pm2_user}" ]]; then
        # Get current user as default
        local default_user=$(whoami)

        # Prompt for PM2 user
        read -p "Enter PM2 user (leave empty to use current user '${default_user}'): " -r user_input

        if [[ -z "$user_input" ]]; then
            # Use default user if no input provided
            pm2_user="${default_user}"
            log_info "Using current user: ${pm2_user}"
        else
            pm2_user="${user_input}"
            log_info "Using specified PM2 user: ${pm2_user}"
        fi
    fi

    # Set current_user for the rest of the function
    local current_user="${pm2_user}"

    # Create directory for PM2 Exporter
    local pm2_exporter_dir="/home/${current_user}/pm2_exporter"
    mkdir -p "${pm2_exporter_dir}"

    # Clone the repository
    log_info "Cloning PM2 Exporter repository"
    git clone "${PM2_EXPORTER_REPO}" "${pm2_exporter_dir}"

    # Install dependencies
    log_info "Installing PM2 Exporter dependencies"
    cd "${pm2_exporter_dir}"
    npm install

    # Start PM2 Exporter using PM2
    log_info "Starting PM2 Exporter using PM2"
    pm2 start pm2_exporter.js

    # Save PM2 process list
    log_info "Saving PM2 process list"
    pm2 save

    # Add to Prometheus configuration
    if command_exists prometheus && [[ -f "/etc/prometheus/prometheus.yml" ]]; then
        add_scrape_config "pm2" "localhost:${PM2_EXPORTER_PORT}"
    else
        log_warning "Prometheus is not installed. You will need to configure it manually to scrape PM2 Exporter."
    fi

    log_success "PM2 Exporter installed successfully"
}

# Check PM2 Exporter status
check_pm2_exporter() {
    log_info "Checking PM2 Exporter status"

    # Check if PM2 is installed
    if ! command_exists pm2; then
        log_error "PM2 is not installed"
        return 1
    fi

    # Check if PM2 Exporter is running
    if ! pm2 list | grep -q "pm2_exporter"; then
        log_error "PM2 Exporter is not running"
        return 1
    fi

    # Check if PM2 Exporter is responding
    if ! curl -s "http://localhost:${PM2_EXPORTER_PORT}/metrics" &>/dev/null; then
        log_error "PM2 Exporter is not responding"
        return 1
    fi

    log_success "PM2 Exporter is installed and running"
    return 0
}

# Uninstall PM2 Exporter
uninstall_pm2_exporter() {
    local pm2_user=${1:-$PM2_USER}

    log_info "Uninstalling PM2 Exporter"

    # Get current user if PM2 user is not specified
    local current_user
    if [[ -z "${pm2_user}" ]]; then
        current_user=$(whoami)
        log_info "No PM2 user specified, using current user: ${current_user}"
    else
        current_user="${pm2_user}"
        log_info "Using specified PM2 user: ${current_user}"
    fi

    # Stop PM2 Exporter
    if pm2 list | grep -q "pm2_exporter"; then
        log_info "Stopping PM2 Exporter"
        pm2 delete pm2_exporter
        pm2 save
    fi

    # Remove PM2 Exporter directory
    local pm2_exporter_dir="/home/${current_user}/pm2_exporter"
    if [[ -d "${pm2_exporter_dir}" ]]; then
        log_info "Removing PM2 Exporter directory"
        rm -rf "${pm2_exporter_dir}"
    fi

    # Remove from Prometheus configuration if Prometheus is installed
    if [[ -f "/etc/prometheus/prometheus.yml" ]]; then
        log_info "Removing PM2 Exporter from Prometheus configuration"
        sed -i '/job_name: .pm2./,+3d' /etc/prometheus/prometheus.yml

        # Restart Prometheus if it's running
        if systemctl is-active --quiet prometheus; then
            systemctl restart prometheus
        fi
    fi

    log_success "PM2 Exporter uninstalled"
}