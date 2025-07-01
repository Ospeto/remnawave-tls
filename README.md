remnawave-tls
Automation Scripts for Xray Node and Remnawave Panel SSL Certificate Management
Overview
This repository contains a set of powerful automation scripts designed to simplify the management of SSL certificates for your Xray Nodes, specifically when integrating with a Remnawave Panel. These scripts automate the processes of obtaining SSL certificates on your Node VPS and securely transferring/configuring them on your Panel VPS, making your Xray deployments more secure and efficient.

Whether you're setting up new nodes or managing existing ones, these scripts streamline certificate handling, reducing manual errors and saving you valuable time.

Features
get_node_cert.sh (Bash Script - Run on Node VPS):

Automates the process of obtaining SSL certificates from Let's Encrypt on your Xray Node VPS.

Guides you through setting up Certbot and choosing between HTTP or DNS validation methods.

User-friendly interactive prompts for domain name and email.

manage_xray_certs_password_auth.py (Python Script - Run on Panel VPS):

Securely copies obtained SSL certificates from your Node VPS to your Remnawave Panel VPS.

Automatically updates your Remnawave Panel's docker-compose.yml file to correctly mount the new certificates.

Restarts your Docker Compose services to apply changes.

Offers flexible SSH authentication methods:

SSH Private Key (recommended for security).

SSH Password (requires sshpass tool on Panel VPS).

Interactive prompts with sensible default paths aligned with Remnawave Panel documentation.

Prerequisites
To use these scripts effectively, ensure you have the following set up:

On your Node VPS (for get_node_cert.sh):
Certbot: The script will attempt to install it if not found.

Domain Name: An active domain name whose A record points to your Node VPS's public IP address.

Port 80 (HTTP validation): Must be open if you choose HTTP validation.

Basic Bash environment.

On your Panel VPS (for manage_xray_certs_password_auth.py):
Remnawave Panel Installation: Ensure your Remnawave Panel is already set up (typically in /opt/remnawave).

Python 3: Installed and available.

pip: For installing Python packages.

pyyaml: Python library for YAML parsing. Install with pip install pyyaml.

sshpass (for Password Authentication): A command-line tool. Install with sudo apt install sshpass on Debian/Ubuntu. Highly recommended if you plan to use password authentication.

SSH Access: Ensure your Panel VPS can SSH/SCP into your Node VPS. If using Private Key, your public key should be on the Node VPS. If using Password, you'll need the Node's SSH user password.

How to Use
Follow these steps to manage your Xray Node SSL certificates:

Step 1: Get SSL Certificate on your Node VPS
Download the script:

Bash

curl -o get_node_cert.sh https://raw.githubusercontent.com/Moe-Kyaw-Aung/remnawave-tls/main/get_node_cert.sh
Make it executable:

Bash

chmod +x get_node_cert.sh
Run the script:

Bash

./get_node_cert.sh
Follow the prompts to provide your Node's domain and email. Choose your preferred validation method (HTTP is usually easiest).

Step 2: Transfer and Configure Certificates on your Panel VPS
Install pyyaml and sshpass (if not already installed):

Bash

pip install pyyaml
sudo apt install sshpass # Only if you plan to use password authentication
Download the script:

Bash

curl -o manage_cert.py https://raw.githubusercontent.com/Moe-Kyaw-Aung/remnawave-tls/main/manage_xray_certs_password_auth.py
Run the script:

Bash

python3 manage_cert.py
Follow the prompts for directories, Node IP, Node Domain, and SSH username.

When prompted, choose your SSH authentication method (Private Key or Password).

If choosing Password: Enter the SSH password for your Node VPS when prompted (input will be hidden).

If choosing Private Key: Provide the path to your SSH private key.

The script will copy the certificates, update your docker-compose.yml, and restart Remnawave.

Step 3: Update Remnawave Panel Configuration (Web UI)
After the Python script completes, you'll see paths printed in the terminal. Use these paths in your Remnawave Panel Web UI:

Log in to your Remnawave Panel (Web UI).

Navigate to the Xray Inbound configuration for your specific Node Domain.

Set the certificate paths as follows (example paths from script output):

"keyFile": "/var/lib/remnawave/configs/xray/ssl/YOUR_NODE_DOMAIN/privkey.pem"

"certificateFile": "/var/lib/remnawave/configs/xray/ssl/YOUR_NODE_DOMAIN/fullchain.pem"

(Remember to replace YOUR_NODE_DOMAIN with your actual domain, e.g., vd5.yamoe.xyz)

Push the updated configuration to your Xray Node.

Important Notes
Security: While password authentication is supported for convenience, using SSH Private Keys is strongly recommended for production environments due to higher security.

Host Key Verification: If you encounter Host key verification failed errors during SSH/SCP, manually SSH into your Node VPS once from your Panel VPS to accept its host key. This adds the key to ~/.ssh/known_hosts, allowing non-interactive commands like scp to proceed. Example: ssh root@your.node.ip.address then type yes.

Paths: The scripts provide sensible defaults based on typical Remnawave installations, but you can always customize them via the interactive prompts if your setup is different.

Contribution
Feel free to open issues or submit pull requests if you have suggestions for improvements or encounter any bugs. Your contributions are welcome!

License
This project is open-source and available under the MIT License. (You'll need to create a LICENSE file in your repository if you don't have one).

