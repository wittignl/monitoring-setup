#!/bin/bash

# PM2 Exporter Installation Module
# Version: 1.0.0
# Installs and configures PM2 Exporter for PM2 process monitoring

install_pm2_exporter() {
    log "Starting PM2 Exporter installation"

    # Verify PM2 is installed for the user
    if ! sudo -u "${PM2_USER}" which pm2 >/dev/null 2>&1; then
        log_error "PM2 is not installed for user ${PM2_USER}"
        exit 1
    fi

    # Create temporary directory for cloning
    local temp_dir="/tmp/pm2_exporter"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"

    # Clone the repository as the PM2 user
    log "Cloning PM2 Exporter repository"
    sudo -u "${PM2_USER}" git clone https://github.com/bblok11/pm2_exporter.git "$temp_dir"

    # Install dependencies as the PM2 user
    log "Installing PM2 Exporter dependencies"
    cd "$temp_dir"
    sudo -u "${PM2_USER}" npm install || {
        log_error "Failed to install PM2 Exporter dependencies"
        exit 1
    }

    # Create final installation directory in the PM2 user's home
    local install_dir
    install_dir=$(sudo -u "${PM2_USER}" bash -c 'echo $HOME')/pm2_exporter
    sudo -u "${PM2_USER}" mkdir -p "$install_dir"

    # Move files to installation directory
    sudo -u "${PM2_USER}" cp -r "$temp_dir"/* "$install_dir/"

    # Clean up temporary directory
    rm -rf "$temp_dir"

    log_success "PM2 Exporter installed"
}

configure_pm2_exporter() {
    log "Configuring PM2 Exporter"

    # Start PM2 Exporter using PM2
    sudo -u "${PM2_USER}" bash -c "cd ~/pm2_exporter && pm2 start pm2_exporter.js"

    # Save PM2 process list to ensure it restarts on reboot
    sudo -u "${PM2_USER}" pm2 save

    log_success "PM2 Exporter configuration completed"
}

install_pm2_exporter_stack() {
    log "Starting PM2 Exporter stack installation"

    install_pm2_exporter
    configure_pm2_exporter

    log_success "PM2 Exporter stack installation completed"
}
