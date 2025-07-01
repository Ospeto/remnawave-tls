#!/bin/bash

# --- Default Configuration Values ---
DEFAULT_REMNAWAVE_COMPOSE_DIR="/opt/remnawave" # Adjust if your Remnawave docker-compose.yml is elsewhere
DEFAULT_PANEL_HOST_CERT_BASE_PATH="/opt/remnawave/ssl_certs"
DEFAULT_CONTAINER_CERT_BASE_PATH="/var/lib/remnawave/configs/xray/ssl"

# --- Function to get user input with a default value ---
get_input_with_default() {
    local prompt="$1"
    local default_value="$2"
    local input_value

    while true; do
        read -rp "${prompt} (default: ${default_value}): " input_value
        if [[ -n "$input_value" ]]; then
            echo "$input_value"
            break
        elif [[ -n "$default_value" ]]; then
            echo "$default_value"
            break
        else
            echo "Input cannot be empty. Please provide a value."
        fi
    done
}

# --- Function to check if a command exists ---
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# --- Main Script ---
echo "--- Xray Node SSL Certificate Automation Script (Bash) for Remnawave Panel ---"
echo "This script will copy certificates from your Node VPS and update Remnawave's Docker Compose."
echo "-----------------------------------------------------------------------------"

# 1. Check for 'yq' tool
echo "Checking for 'yq' tool..."
if ! command_exists yq; then
    echo "Error: 'yq' tool not found. Please install it first."
    echo "  For Ubuntu/Debian: sudo snap install yq"
    echo "  Refer to https://github.com/mikefarah/yq for other installation methods."
    exit 1
else
    echo "'yq' is installed."
fi

# Get User Inputs for Configuration Paths
REMNAWAVE_COMPOSE_DIR=$(get_input_with_default "Enter Remnawave docker-compose.yml directory" "$DEFAULT_REMNAWAVE_COMPOSE_DIR")
PANEL_HOST_CERT_BASE_PATH=$(get_input_with_default "Enter Panel Host Base Certs Directory" "$DEFAULT_PANEL_HOST_CERT_BASE_PATH")
CONTAINER_CERT_BASE_PATH=$(get_input_with_default "Enter Container Base Certs Directory (for Xray config)" "$DEFAULT_CONTAINER_CERT_BASE_PATH")
DOCKER_COMPOSE_FILE="${REMNAWAVE_COMPOSE_DIR}/docker-compose.yml"

# Get Node Specific Inputs
NODE_IP=$(get_input_with_default "Enter Node VPS IP Address" "")
if [[ -z "$NODE_IP" ]]; then
    echo "Node IP Address cannot be empty. Exiting."
    exit 1
fi

NODE_DOMAIN=$(get_input_with_default "Enter Node VPS Domain Name (e.g., node1.example.com)" "")
if [[ -z "$NODE_DOMAIN" ]]; then
    echo "Node Domain Name cannot be empty. Exiting."
    exit 1
fi

SSH_KEY_PATH=$(get_input_with_default "Enter SSH Private Key Path (optional, leave empty if using password or agent)" "")

# Get Node SSH User (default to current user or root)
NODE_USER=$(get_input_with_default "Enter Node VPS SSH Username" "$USER")
if [[ -z "$NODE_USER" ]]; then # If $USER is empty for some reason, default to root
    NODE_USER="root"
fi

echo -e "\n--- Automating SSL Certificate Setup for Node: ${NODE_DOMAIN} (${NODE_IP}) ---"
echo "Remnawave Compose Dir: ${REMNAWAVE_COMPOSE_DIR}"
echo "Panel Host Certs Dir: ${PANEL_HOST_CERT_BASE_PATH}"
echo "Container Certs Dir: ${CONTAINER_CERT_BASE_PATH}"

# --- Function to copy certs from Node VPS ---
copy_certs_from_node() {
    local node_user="$1"
    local node_ip="$2"
    local node_domain="$3"
    local panel_host_cert_base_path="$4"
    local ssh_key_path="$5"

    local node_cert_path="/etc/letsencrypt/live/${node_domain}"
    local panel_node_cert_path="${panel_host_cert_base_path}/${node_domain}"

    echo "Creating destination directory on Panel VPS: ${panel_node_cert_path}"
    sudo mkdir -p "${panel_node_cert_path}" || { echo "Error: Could not create directory."; return 1; }

    echo "Copying SSL Certificates from Node VPS (${node_user}@${node_ip}:${node_cert_path}) to Panel VPS..."
    local scp_command=("scp" "-r")
    if [[ -n "$ssh_key_path" ]]; then
        scp_command+=("-i" "$ssh_key_path")
    fi
    
    scp_command+=("${node_user}@${node_ip}:${node_cert_path}/." "$panel_node_cert_path")

    # Use eval to run the scp command to handle potential quoting/expansion issues with ssh_key_path
    if ! "${scp_command[@]}"; then
        echo "Error: Failed to copy certificates. Check SSH access and paths."
        return 1
    fi

    echo "Certificates copied successfully."
    echo "$panel_node_cert_path" # Return the path for later use
}

# --- Function to update docker-compose.yml volumes using yq ---
update_docker_compose_volumes() {
    local docker_compose_file="$1"
    local node_domain="$2"
    local panel_node_cert_path="$3"
    local container_cert_base_path="$4"

    echo "Updating ${docker_compose_file} for volume mount using yq..."

    # Define the new volume mount string
    local container_node_cert_path="${container_cert_base_path}/${node_domain}"
    local new_volume_mount="${panel_node_cert_path}:${container_node_cert_path}"

    # Check if the volume mount already exists
    # yq '.services.remnawave.volumes[]' docker-compose.yml will list all volumes
    if yq ".services.remnawave.volumes[] | select(. == \"${new_volume_mount}\")" "${docker_compose_file}" > /dev/null 2>&1; then
        echo "Volume mount already exists: ${new_volume_mount}. No changes needed for docker-compose.yml."
    else
        echo "Adding new volume mount: ${new_volume_mount}"
        # Use yq to append the new volume mount
        if ! yq ".services.remnawave.volumes += [\"${new_volume_mount}\"]" -i "${docker_compose_file}"; then
            echo "Error: Failed to add volume mount to docker-compose.yml. Check file structure and yq syntax."
            return 1
        fi
        echo "docker-compose.yml updated successfully."
    fi
    echo "$container_node_cert_path" # Return the path for later use
}

# --- Function to restart Docker Compose ---
restart_docker_compose() {
    local remnawave_compose_dir="$1" # Updated variable name
    echo "Restarting Docker Compose to apply changes..."
    
    cd "${remnawave_compose_dir}" || { echo "Error: Could not change to Remnawave compose directory."; return 1; } # Updated variable name
    
    if ! sudo docker compose down; then
        echo "Error: Failed to stop Docker Compose."; return 1;
    fi
    if ! sudo docker compose up -d; then
        echo "Error: Failed to start Docker Compose."; return 1;
    fi
    echo "Docker Compose restarted successfully."
}

# --- Main Execution Flow ---
if ! PANEL_HOST_NODE_CERT_PATH=$(copy_certs_from_node "$NODE_USER" "$NODE_IP" "$NODE_DOMAIN" "$PANEL_HOST_CERT_BASE_PATH" "$SSH_KEY_PATH"); then
    echo "Script aborted due to certificate copy error."
    exit 1
fi

if ! CONTAINER_NODE_CERT_PATH=$(update_docker_compose_volumes "$DOCKER_COMPOSE_FILE" "$NODE_DOMAIN" "$PANEL_HOST_NODE_CERT_PATH" "$CONTAINER_CERT_BASE_PATH"); then
    echo "Script aborted due to docker-compose.yml update error."
    exit 1
fi

if ! restart_docker_compose "$REMNAWAVE_COMPOSE_DIR"; then # Updated variable name
    echo "Script aborted due to Docker Compose restart error."
    exit 1
fi

echo -e "\n--- Automation Complete ---"
echo "SSL Certificate setup for ${NODE_DOMAIN} is complete on Panel VPS."
echo "Next Steps:"
echo "1. Log in to your Remnawave Panel (Web UI)."
echo "2. When configuring the Xray Inbound for ${NODE_DOMAIN}, ensure you set the certificate paths as follows:"
echo "   \"keyFile\": \"${CONTAINER_NODE_CERT_PATH}/privkey.pem\","
echo "   \"certificateFile\": \"${CONTAINER_NODE_CERT_PATH}/fullchain.pem\""
echo "   (Note: Use .pem for both, as Let's Encrypt typically provides privkey.pem)"
echo "3. Push the updated configuration to your Xray Node."
echo -e "\nExcellent work, Squall! You've mastered automation with Bash!"
