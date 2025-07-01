#!/bin/bash

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
echo "--- Xray Node SSL Certificate Acquisition Script ---"
echo "This script will help you obtain an SSL Certificate from Let's Encrypt for your Xray Node."
echo "Please ensure your domain's A record points to this VPS's Public IP address."
echo "----------------------------------------------------"

# 1. Update system and install Certbot
echo "Checking for Certbot installation..."
if ! command_exists certbot; then
    echo "Certbot not found. Installing Certbot..."
    sudo apt update || { echo "Failed to update system. Exiting."; exit 1; }
    sudo apt install -y certbot || { echo "Failed to install Certbot. Exiting."; exit 1; }
    echo "Certbot installed successfully."
else
    echo "Certbot is already installed."
fi

# 2. Get User Inputs
echo -e "\n--- Enter Your Node's Domain Information ---"
NODE_DOMAIN=$(get_input_with_default "Enter your Node's Domain Name (e.g., node1.yourdomain.com)" "")
if [[ -z "$NODE_DOMAIN" ]]; then
    echo "Domain Name cannot be empty. Exiting."
    exit 1
fi

ADMIN_EMAIL=$(get_input_with_default "Enter your Email Address for urgent renewals/security notices (e.g., your@example.com)" "")
if [[ -z "$ADMIN_EMAIL" ]]; then
    echo "Email Address cannot be empty. Exiting."
    exit 1
fi

# Determine validation method
echo -e "\n--- Choose Certificate Validation Method ---"
echo "1) HTTP validation (Recommended: Requires Port 80 to be open)"
echo "2) DNS validation (Requires manual DNS TXT record addition)"
VALIDATION_METHOD=$(get_input_with_default "Enter your choice (1 or 2)" "1")

CERT_COMMAND=""
case "$VALIDATION_METHOD" in
    1)
        echo "Using HTTP validation (certonly --standalone)."
        echo "Please ensure Port 80 (HTTP) is open and accessible from the internet."
        CERT_COMMAND="sudo certbot certonly --standalone -d ${NODE_DOMAIN} --email ${ADMIN_EMAIL} --agree-tos --no-eff-email"
        ;;
    2)
        echo "Using DNS validation (--manual --preferred-challenges dns)."
        echo "You will need to manually add a DNS TXT record to your domain's DNS settings."
        CERT_COMMAND="sudo certbot certonly --manual --preferred-challenges dns -d ${NODE_DOMAIN} --email ${ADMIN_EMAIL} --agree-tos --no-eff-email"
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

# 3. Execute Certbot Command
echo -e "\n--- Executing Certbot ---"
echo "Command: ${CERT_COMMAND}"
if eval "$CERT_COMMAND"; then
    echo -e "\n--- SSL Certificate Obtained Successfully! ---"
    echo "Your certificates are located at: /etc/letsencrypt/live/${NODE_DOMAIN}/"
    echo "Specifically:"
    echo "  Private Key: /etc/letsencrypt/live/${NODE_DOMAIN}/privkey.pem"
    echo "  Full Chain Certificate: /etc/letsencrypt/live/${NODE_DOMAIN}/fullchain.pem"
    echo "You can now copy these files to your Panel VPS."
else
    echo -e "\n--- Failed to Obtain SSL Certificate ---"
    echo "Please check the error messages above and ensure:"
    echo "1. Your domain's A record correctly points to this VPS's IP."
    echo "2. Port 80 is open if you chose HTTP validation."
    echo "3. Your DNS TXT record is correctly added if you chose DNS validation."
    exit 1
fi

echo -e "\n--- Script Complete ---"
echo "Now, you can use the 'manage_xray_certs_interactive.py' script on your Panel VPS"
echo "to copy these certificates and update your Marzban Docker Compose configuration."
echo "Good job, Squall! One step closer to full automation and a more secure setup!"
