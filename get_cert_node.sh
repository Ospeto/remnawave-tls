#!/bin/bash

# --- Default Configuration Values ---
DEFAULT_XRAY_CONFIG_PATH="/usr/local/etc/xray/config.json" # Common Xray config path
DEFAULT_LE_CERT_BASE_PATH="/etc/letsencrypt/live" # Standard Let's Encrypt certs path

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
echo "--- Xray Node SSL Certificate Path Updater (Bash) ---"
echo "This script will find your Let's Encrypt certificates and update your Xray config.json."
echo "-----------------------------------------------------"

# 1. Check for 'jq' tool
echo "Checking for 'jq' tool (JSON processor)..."
if ! command_exists jq; then
    echo "Error: 'jq' tool not found. Please install it first."
    echo "  For Ubuntu/Debian: sudo apt update && sudo apt install -y jq"
    echo "  Refer to https://stedolan.github.io/jq/ for other installation methods."
    exit 1
else
    echo "'jq' is installed."
fi

# Get User Inputs
NODE_DOMAIN=$(get_input_with_default "Enter Node Domain Name (e.g., node1.example.com for which certs are issued)" "")
if [[ -z "$NODE_DOMAIN" ]]; then
    echo "Node Domain Name cannot be empty. Exiting."
    exit 1
fi

XRAY_CONFIG_FILE=$(get_input_with_default "Enter Xray config.json path" "$DEFAULT_XRAY_CONFIG_PATH")
if [[ ! -f "$XRAY_CONFIG_FILE" ]]; then
    echo "Error: Xray config file not found at ${XRAY_CONFIG_FILE}. Please provide the correct path."
    exit 1
fi

# Determine certificate paths
CERT_DIR="${DEFAULT_LE_CERT_BASE_PATH}/${NODE_DOMAIN}"
PRIVKEY_PATH="${CERT_DIR}/privkey.pem"
FULLCHAIN_PATH="${CERT_DIR}/fullchain.pem"

if [[ ! -f "$PRIVKEY_PATH" || ! -f "$FULLCHAIN_PATH" ]]; then
    echo "Error: SSL certificates not found for ${NODE_DOMAIN} at ${CERT_DIR}."
    echo "Please ensure Let's Encrypt certificates are issued and located there."
    exit 1
fi

echo -e "\n--- Configuration Summary ---"
echo "Node Domain: ${NODE_DOMAIN}"
echo "Xray Config File: ${XRAY_CONFIG_FILE}"
echo "Private Key Path: ${PRIVKEY_PATH}"
echo "Fullchain Cert Path: ${FULLCHAIN_PATH}"
echo "-----------------------------"

# Find the tag for the inbound that uses TLS
echo -e "\nSearching for TLS inbound tag in ${XRAY_CONFIG_FILE}..."
# This finds the tag of the inbound that has streamSettings.security as "tls" AND has "serverName" matching NODE_DOMAIN
TLS_INBOUND_TAG=$(jq -r ".inbounds[] | select(.streamSettings.security == \"tls\" and .streamSettings.tlsSettings.serverName == \"${NODE_DOMAIN}\") | .tag" "$XRAY_CONFIG_FILE")

if [[ -z "$TLS_INBOUND_TAG" ]]; then
    echo "Error: Could not find an Xray inbound with TLS security and serverName matching '${NODE_DOMAIN}'."
    echo "Please ensure your Xray config has a TLS inbound for this domain."
    echo "Exiting."
    exit 1
else
    echo "Found TLS inbound tag: '${TLS_INBOUND_TAG}'"
fi

# Backup the original Xray config
echo "Creating a backup of your Xray config: ${XRAY_CONFIG_FILE}.bak"
sudo cp "$XRAY_CONFIG_FILE" "${XRAY_CONFIG_FILE}.bak" || { echo "Error: Failed to create backup. Exiting."; exit 1; }

echo "Updating certificate paths in Xray config.json using 'jq'..."

# Update the certificate paths for the identified inbound tag
# Construct the jq filter dynamically
JQ_FILTER="
.inbounds[] |= if .tag == \"${TLS_INBOUND_TAG}\" then
    .streamSettings.tlsSettings.certificates[0].keyFile = \"${PRIVKEY_PATH}\" |
    .streamSettings.tlsSettings.certificates[0].certificateFile = \"${FULLCHAIN_PATH}\"
else
    .
end
"

if ! sudo jq "$JQ_FILTER" "${XRAY_CONFIG_FILE}" | sudo tee "${XRAY_CONFIG_FILE}.tmp" > /dev/null; then
    echo "Error: Failed to update Xray config with 'jq'. Check JSON syntax or permissions."
    echo "Original config restored from backup (if created)."
    sudo mv "${XRAY_CONFIG_FILE}.bak" "${XRAY_CONFIG_FILE}" 2>/dev/null
    exit 1
fi

# Replace the original file with the updated one
sudo mv "${XRAY_CONFIG_FILE}.tmp" "${XRAY_CONFIG_FILE}" || { echo "Error: Failed to move temporary config file. Exiting."; exit 1; }

echo "Xray config.json updated successfully."

# Restart Xray Service
echo "Restarting Xray service to apply changes..."
if command_exists systemctl; then
    sudo systemctl restart xray || { echo "Error: Failed to restart Xray service. Check 'sudo systemctl status xray'."; exit 1; }
    sudo systemctl status xray --no-pager || { echo "Check Xray service status manually."; }
elif command_exists docker; then
    # Assuming Xray is in a container named 'xray' or 'remnawave_xray' or similar
    # This might need manual adjustment if container name is different
    echo "Attempting to restart Xray Docker container..."
    XRAY_CONTAINER_NAME=$(sudo docker ps --format '{{.Names}}' | grep -i "xray\|remnawave")
    if [[ -z "$XRAY_CONTAINER_NAME" ]]; then
        echo "Warning: Could not find a running Xray/Remnawave container. Please restart manually."
    else
        sudo docker restart "$XRAY_CONTAINER_NAME" || { echo "Error: Failed to restart Xray Docker container. Check 'sudo docker logs $XRAY_CONTAINER_NAME'."; exit 1; }
        echo "Xray Docker container '$XRAY_CONTAINER_NAME' restarted successfully."
        echo "Check logs: sudo docker logs -f $XRAY_CONTAINER_NAME"
    fi
else
    echo "Warning: Cannot determine how to restart Xray service. Please restart manually."
fi

echo -e "\n--- Automation Complete ---"
echo "SSL Certificate paths for ${NODE_DOMAIN} have been updated in ${XRAY_CONFIG_FILE}."
echo "Please verify Xray logs for any errors after restart (e.g., sudo journalctl -u xray -f or sudo docker logs -f <container_name>)."
echo -e "\nExcellent work, Squall! You've successfully automated your Xray certificate updates on the Node!"
