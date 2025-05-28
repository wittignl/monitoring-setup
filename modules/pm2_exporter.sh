#!/bin/bash
#
# PM2 Exporter installation functions (User-centric approach)
# Installs/Uninstalls PM2 Exporter under a specified user using their PM2 instance.
#

PM2_EXPORTER_PORT="9116"
PM2_EXPORTER_REPO="https://github.com/bblok11/pm2_exporter.git"
PM2_EXPORTER_APP_NAME="pm2-prometheus-exporter"

run_as_user() {
    local user="$1"
    local user_home
    local command_to_run

    user_home=$(eval echo "~$user")
    if [[ -z "$user_home" || ! -d "$user_home" ]]; then
        log_error "Could not determine home directory for user '$user'."
        return 1
    fi

    # Read the command: if stdin is not a tty, read from stdin (heredoc), otherwise use remaining args
    if [[ ! -t 0 ]]; then
        command_to_run=$(cat)
    else
        shift # Remove user from args
        command_to_run="$*"
    fi

    # Construct the full command string for runuser, including NVM sourcing
    # Use double quotes inside for variables like $HOME that should be expanded by the user's shell
    local nvm_source_cmd="export NVM_DIR=\"\$HOME/.nvm\"; if [[ -s \"\$NVM_DIR/nvm.sh\" ]]; then source \"\$NVM_DIR/nvm.sh\"; else echo 'WARN: NVM script not found for user $user' >&2; fi"
    # Ensure the actual command runs with 'set -e' if it's a script block
    local final_command_for_runuser="set -e; ${nvm_source_cmd}; ${command_to_run}"


    # Execute using runuser -l for login environment, -s to specify bash, -c for the command string
    if runuser -l "$user" -s /bin/bash -c "$final_command_for_runuser"; then
        return 0
    else
        log_error "Command execution failed for user '$user': ${command_to_run:0:100}..." # Log truncated command
        return 1
    fi
}

install_pm2_exporter() {
    local PM2_USER="$1"
    local PM2_USER_HOME

    if [[ -z "$PM2_USER" ]]; then
        log_error "PM2 user argument is required for install_pm2_exporter."
        return 1
    fi
    log_info "Starting PM2 Exporter installation for user: ${PM2_USER}"

    PM2_USER_HOME=$(eval echo "~$PM2_USER")
    if [[ -z "$PM2_USER_HOME" || ! -d "$PM2_USER_HOME" ]]; then
        log_error "Could not determine home directory for user '$PM2_USER'."
        return 1
    fi

    local PM2_EXPORTER_INSTALL_DIR="${PM2_USER_HOME}/monitoring/pm2_exporter"

    log_info "Ensuring NVM, Node.js (LTS), and PM2 are installed for user ${PM2_USER}..."
    run_as_user "$PM2_USER" <<'RUNCMD' || handle_error "Failed to set up NVM/Node/PM2 for user ${PM2_USER}"
if ! command -v nvm &> /dev/null; then
    echo "NVM not found, installing for user ${PM2_USER}..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        source "$NVM_DIR/nvm.sh"
        echo "NVM sourced successfully after installation."
    else
        echo "ERROR: Failed to source NVM immediately after installation for ${PM2_USER}." >&2
        exit 1
    fi
else
    echo "NVM is already installed."
fi

if ! nvm list lts/* &>/dev/null || ! nvm list | grep -q "lts/\* ->"; then
    echo "Node.js LTS not found or alias missing, installing/aliasing..."
    nvm install --lts
    nvm alias default lts/*
    nvm use default
else
    echo "Node.js LTS is already installed."
    nvm use default
fi

if ! command -v pm2 &> /dev/null; then
    echo "PM2 not found, installing globally (for the user) via npm..."
    npm install -g pm2
else
    echo "PM2 is already installed."
fi

echo "NVM/Node/PM2 setup check completed for user ${PM2_USER}."
RUNCMD

    log_info "Cloning/Updating PM2 Exporter repository for user ${PM2_USER} in ${PM2_EXPORTER_INSTALL_DIR}"
    run_as_user "$PM2_USER" <<RUNCMD || handle_error "Failed to clone/update PM2 Exporter repository for user ${PM2_USER}"
set -e
echo "Attempting clone/update in ${PM2_EXPORTER_INSTALL_DIR}"
mkdir -p "$(dirname "${PM2_EXPORTER_INSTALL_DIR}")"

if [[ -d "${PM2_EXPORTER_INSTALL_DIR}" ]]; then
    echo 'Repository directory exists, attempting pull...'
    cd "${PM2_EXPORTER_INSTALL_DIR}"
    if timeout 60s git pull; then
        echo "Git pull successful."
    else
        echo "ERROR: git pull timed out or failed." >&2
        exit 1
    fi
else
    echo 'Cloning repository...'
    if timeout 60s git clone --verbose "https://github.com/bblok11/pm2_exporter.git" "${PM2_EXPORTER_INSTALL_DIR}"; then
        echo "Git clone successful."
    else
        echo "ERROR: git clone timed out or failed." >&2
        exit 1
    fi
fi
echo "Clone/update step finished."
RUNCMD

    log_info "Installing PM2 Exporter dependencies for user ${PM2_USER} in ${PM2_EXPORTER_INSTALL_DIR}"
    run_as_user "$PM2_USER" <<RUNCMD || handle_error "Failed to install PM2 Exporter dependencies for user ${PM2_USER}"
set -e
target_dir="${PM2_EXPORTER_INSTALL_DIR}"
echo "Changing to directory: \${target_dir}"
cd "\${target_dir}" || { echo "ERROR: Failed to cd to \${target_dir}"; exit 1; }
echo "Current directory: \$(pwd)"
echo "Running npm install in \$(pwd)..."
if timeout 120s npm install; then
    echo "npm install successful."
else
    echo "ERROR: npm install timed out or failed in \$(pwd)." >&2
    exit 1
fi
echo "npm install step finished."
RUNCMD

    log_info "Starting/Restarting PM2 Exporter process (${PM2_EXPORTER_APP_NAME}) using PM2 for user ${PM2_USER}"
    run_as_user "$PM2_USER" "
        cd \"${PM2_EXPORTER_INSTALL_DIR}\"
        pm2 start pm2_exporter.js --name \"${PM2_EXPORTER_APP_NAME}\" -- --web.listen-address=127.0.0.1:${PM2_EXPORTER_PORT} --restart-delay 5000 --max-restarts 10 || pm2 restart \"${PM2_EXPORTER_APP_NAME}\"
        pm2 save
    " || handle_error "Failed to start/restart PM2 Exporter process for user ${PM2_USER}"

    log_info "Checking if PM2 Exporter is responding on 127.0.0.1:${PM2_EXPORTER_PORT}"
    sleep 5
    if ! curl --fail -s "http://127.0.0.1:${PM2_EXPORTER_PORT}/metrics" &>/dev/null; then
        log_error "PM2 Exporter started via PM2 but not responding on http://127.0.0.1:${PM2_EXPORTER_PORT}/metrics"
    else
        log_success "PM2 Exporter is running via PM2 and responding."
    fi

    if command_exists prometheus && [[ -f "/etc/prometheus/prometheus.yml" ]]; then
        add_prometheus_scrape_config "pm2" "127.0.0.1:${PM2_EXPORTER_PORT}"
    else
        log_warning "Prometheus is not installed or config file not found. Configure manually to scrape PM2 Exporter."
    fi

    log_success "PM2 Exporter setup completed for user ${PM2_USER}"
}


uninstall_pm2_exporter() {
    local PM2_USER="$1"
    local PM2_USER_HOME

    if [[ -z "$PM2_USER" ]]; then
        log_error "PM2 user argument is required for uninstall_pm2_exporter."
        return 1
    fi
    log_info "Starting PM2 Exporter uninstallation for user: ${PM2_USER}"

    PM2_USER_HOME=$(eval echo "~$PM2_USER")
     if [[ -z "$PM2_USER_HOME" || ! -d "$PM2_USER_HOME" ]]; then
        log_warning "Could not determine home directory for user '$PM2_USER'. Skipping removal of install dir."
    fi
    local PM2_EXPORTER_INSTALL_DIR="${PM2_USER_HOME}/monitoring/pm2_exporter"


    log_info "Stopping and deleting PM2 process '${PM2_EXPORTER_APP_NAME}' for user ${PM2_USER}"
    # Check if process exists before trying to stop/delete
    process_status=$(runuser -l "$PM2_USER" -s /bin/bash -c "export NVM_DIR=\"\$HOME/.nvm\"; [[ -s \"\$NVM_DIR/nvm.sh\" ]] && source \"\$NVM_DIR/nvm.sh\"; pm2 describe ${PM2_EXPORTER_APP_NAME} &> /dev/null; echo \$?")

    if [[ "$process_status" -eq 0 ]]; then
        log_info "PM2 process '${PM2_EXPORTER_APP_NAME}' found, attempting stop/delete..."
        local nvm_cmd="export NVM_DIR=\"\$HOME/.nvm\"; [[ -s \"\$NVM_DIR/nvm.sh\" ]] && source \"\$NVM_DIR/nvm.sh\";"
        if ! runuser -l "$PM2_USER" -s /bin/bash -c "${nvm_cmd} pm2 stop \"${PM2_EXPORTER_APP_NAME}\""; then
            log_warning "Failed to stop PM2 process '${PM2_EXPORTER_APP_NAME}' for user ${PM2_USER} (maybe already stopped?)."
        fi
        if ! runuser -l "$PM2_USER" -s /bin/bash -c "${nvm_cmd} pm2 delete \"${PM2_EXPORTER_APP_NAME}\""; then
             log_warning "Failed to delete PM2 process '${PM2_EXPORTER_APP_NAME}' for user ${PM2_USER} (maybe already deleted?)."
        fi
        if ! runuser -l "$PM2_USER" -s /bin/bash -c "${nvm_cmd} pm2 save --force"; then
             log_warning "Failed to save PM2 state for user ${PM2_USER} after delete."
        fi
    else
        log_info "PM2 process '${PM2_EXPORTER_APP_NAME}' not found for user ${PM2_USER}. Skipping stop/delete."
        # Still attempt pm2 save in case of orphaned entries
        run_as_user "$PM2_USER" "pm2 save --force" || log_warning "Failed to run 'pm2 save --force' for user ${PM2_USER}."
    fi

    if [[ -n "$PM2_USER_HOME" && -d "${PM2_EXPORTER_INSTALL_DIR}" ]]; then
        log_info "Removing installation directory: ${PM2_EXPORTER_INSTALL_DIR}"
        rm -rf "${PM2_EXPORTER_INSTALL_DIR}" || log_warning "Failed to remove directory ${PM2_EXPORTER_INSTALL_DIR}"
    else
         log_info "Installation directory not found or user home unknown, skipping removal: ${PM2_EXPORTER_INSTALL_DIR}"
    fi

    if [[ -f "/etc/prometheus/prometheus.yml" ]]; then
        log_info "Removing PM2 Exporter from Prometheus configuration"
        # Remove the job configuration block using sed
        sed -i "/^\s*-\s*job_name:\s*'pm2'/,+2d" /etc/prometheus/prometheus.yml
        # Reload Prometheus if it's running
        reload_prometheus_config
    fi

    log_success "PM2 Exporter uninstalled for user ${PM2_USER}"
}

check_pm2_exporter() {
     local PM2_USER="$1"

     log_info "Checking if PM2 Exporter is responding on 127.0.0.1:${PM2_EXPORTER_PORT}"
     if ! curl --fail -s "http://127.0.0.1:${PM2_EXPORTER_PORT}/metrics" &>/dev/null; then
         log_error "PM2 Exporter is not responding on http://127.0.0.1:${PM2_EXPORTER_PORT}/metrics"
         return 1
     fi

     log_success "PM2 Exporter is responding."
     return 0
}