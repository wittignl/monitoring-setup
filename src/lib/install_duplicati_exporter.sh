#!/bin/bash

# Duplicati Exporter Installation Module
# Version: 1.0.0
# Installs and configures Duplicati Exporter for backup monitoring

install_duplicati_exporter() {
    log "Starting Duplicati Exporter installation"

    # Verify PM2 is installed for the user
    if ! sudo -u "${PM2_USER}" which pm2 >/dev/null 2>&1; then
        log_error "PM2 is not installed for user ${PM2_USER}"
        exit 1
    fi

    # Create temporary directory for cloning
    local temp_dir="/tmp/duplicati_exporter"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"

    # Clone the repository as the PM2 user
    log "Cloning Duplicati Exporter repository"
    sudo -u "${PM2_USER}" git clone https://github.com/wittignl/duplicati_exporter.git "$temp_dir"

    # Install dependencies as the PM2 user
    log "Installing Duplicati Exporter dependencies"
    cd "$temp_dir"
    sudo -u "${PM2_USER}" npm install || {
        log_error "Failed to install Duplicati Exporter dependencies"
        exit 1
    }

    # Create final installation directory in the PM2 user's home
    local install_dir
    install_dir=$(sudo -u "${PM2_USER}" bash -c 'echo $HOME')/duplicati_exporter
    sudo -u "${PM2_USER}" mkdir -p "$install_dir"

    # Move files to installation directory
    sudo -u "${PM2_USER}" cp -r "$temp_dir"/* "$install_dir/"

    # Clean up temporary directory
    rm -rf "$temp_dir"

    log_success "Duplicati Exporter installed"
}

configure_duplicati_exporter() {
    log "Configuring Duplicati Exporter"

    # Start Duplicati Exporter using PM2
    sudo -u "${PM2_USER}" bash -c "cd ~/duplicati_exporter && pm2 start duplicati_exporter.js --name duplicati_exporter -- -p 9118"

    # Save PM2 process list to ensure it restarts on reboot
    sudo -u "${PM2_USER}" pm2 save

    log_success "Duplicati Exporter configuration completed"
}

install_duplicati_exporter_stack() {
    log "Starting Duplicati Exporter stack installation"

    install_duplicati_exporter
    configure_duplicati_exporter

    log_success "Duplicati Exporter stack installation completed"
}
