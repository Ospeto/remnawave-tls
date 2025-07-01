import os
import subprocess
import yaml
import sys
import getpass # For securely getting password

# --- Configuration (Default values, will be overridden by user input if prompted) ---
DEFAULT_REMNAWAVE_COMPOSE_DIR = "/opt/remnawave"
PANEL_HOST_CERT_BASE_PATH = "/opt/remnawave/ssl_certs"
CONTAINER_CERT_BASE_PATH = "/var/lib/remnawave/configs/xray/ssl"

# --- Functions ---

def run_command(command, cwd=None, shell=False, check=True, capture_output=False, text=False, env=None):
    """Helper function to run shell commands."""
    print(f"\nExecuting: {' '.join(command) if isinstance(command, list) else command}")
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            shell=shell,
            check=check,
            capture_output=capture_output,
            text=text,
            env=env # Pass environment variables (e.g., SSHPASS)
        )
        if capture_output:
            print("STDOUT:\n", result.stdout)
            if result.stderr:
                print("STDERR:\n", result.stderr)
        return result
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {e}")
        if e.stdout:
            print("STDOUT:\n", e.stdout)
        if e.stderr:
            print("STDERR:\n", e.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print(f"Error: Command not found. Make sure '{command[0]}' is in your PATH. If using sshpass, ensure it's installed.")
        sys.exit(1)

def copy_certs_from_node(node_user, node_ip, node_domain, panel_host_cert_base_path, ssh_key_path=None, ssh_password=None):
    """Copies SSL certificates from the Node VPS to the Panel VPS."""
    node_cert_path = f"/etc/letsencrypt/live/{node_domain}"
    panel_node_cert_path = os.path.join(panel_host_cert_base_path, node_domain)

    print(f"Creating destination directory on Panel VPS: {panel_node_cert_path}")
    run_command(["sudo", "mkdir", "-p", panel_node_cert_path])

    print(f"Copying SSL Certificates from Node VPS ({node_user}@{node_ip}:{node_cert_path}) to Panel VPS...")
    
    scp_command = []
    env_vars = os.environ.copy() # Make a copy of current environment variables

    if ssh_password:
        if not getpass_command_exists():
            print("Error: 'sshpass' command not found. Please install it to use password authentication.")
            print("  For Debian/Ubuntu: sudo apt install sshpass")
            sys.exit(1)
        scp_command.append("sshpass")
        scp_command.append("-p")
        scp_command.append(ssh_password) # sshpass will read this password
        scp_command.append("scp")
    else: # Default to scp directly (will prompt for password if no key or agent)
        scp_command.append("scp")

    scp_command.append("-r")
    if ssh_key_path:
        scp_command.extend(["-i", ssh_key_path])
    
    scp_command.append(f"{node_user}@{node_ip}:{node_cert_path}/.")
    scp_command.append(panel_node_cert_path)

    run_command(scp_command, env=env_vars) # Pass environment variables here
    print("Certificates copied successfully.")
    return panel_node_cert_path

def update_docker_compose_volumes(docker_compose_file, node_domain, panel_node_cert_path, container_cert_base_path):
    """Updates the docker-compose.yml file with the new volume mount."""
    print(f"Updating {docker_compose_file} for volume mount...")

    try:
        with open(docker_compose_file, 'r') as f:
            compose_config = yaml.safe_load(f)
    except FileNotFoundError:
        print(f"Error: {docker_compose_file} not found. Please check the path.")
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"Error parsing YAML file: {e}")
        sys.exit(1)

    if 'services' not in compose_config or 'remnawave' not in compose_config['services']:
        print("Error: 'remnawave' service not found in docker-compose.yml. Make sure your docker-compose.yml is for Remnawave Panel backend.")
        sys.exit(1)

    remnawave_service = compose_config['services']['remnawave']

    if 'volumes' not in remnawave_service:
        remnawave_service['volumes'] = []

    container_node_cert_path = os.path.join(container_cert_base_path, node_domain)
    new_volume_mount = f"{panel_node_cert_path}:{container_node_cert_path}"

    if new_volume_mount not in remnawave_service['volumes']:
        remnawave_service['volumes'].append(new_volume_mount)
        print(f"Added new volume mount: {new_volume_mount}")
    else:
        print(f"Volume mount already exists: {new_volume_mount}. No changes needed for docker-compose.yml.")

    with open(docker_compose_file, 'w') as f:
        yaml.safe_dump(compose_config, f, default_flow_style=False, indent=2)
    print("docker-compose.yml updated successfully.")
    return container_node_cert_path

def restart_docker_compose(remnawave_compose_dir):
    """Restarts Docker Compose."""
    print("Restarting Docker Compose to apply changes...")
    run_command(["sudo", "docker", "compose", "down"], cwd=remnawave_compose_dir)
    run_command(["sudo", "docker", "compose", "up", "-d"], cwd=remnawave_compose_dir)
    print("Docker Compose restarted successfully.")

def get_user_input(prompt, default_value):
    """Gets user input with a default value."""
    while True:
        default_display = "" if default_value is None or default_value == "" else f" (default: {default_value})"
        user_input = input(f"{prompt}{default_display}: ").strip()
        if user_input:
            return user_input
        elif default_value is not None and default_value != "":
            return default_value
        else:
            print("Input cannot be empty. Please provide a value.")

def getpass_command_exists():
    """Checks if sshpass command exists."""
    return subprocess.run(["which", "sshpass"], capture_output=True).returncode == 0

# --- Main Script Execution ---

if __name__ == "__main__":
    print("--- Xray Node SSL Certificate Automation Script (for Remnawave Panel) ---")

    remnawave_compose_dir = get_user_input("Enter Remnawave docker-compose.yml directory", DEFAULT_REMNAWAVE_COMPOSE_DIR)
    panel_host_cert_base_path = get_user_input("Enter Panel Host Base Certs Directory", PANEL_HOST_CERT_BASE_PATH)
    container_cert_base_path = get_user_input("Enter Container Base Certs Directory (for Xray config)", CONTAINER_CERT_BASE_PATH)
    docker_compose_file = os.path.join(remnawave_compose_dir, "docker-compose.yml")

    node_ip = get_user_input("Enter Node VPS IP Address", None)
    node_domain = get_user_input("Enter Node VPS Domain Name (e.g., node1.example.com)", None)
    node_user = get_user_input("Enter Node VPS SSH Username", os.getenv("USER", "root"))

    print("\n--- SSH Authentication Method ---")
    print("1. Use SSH Private Key (Recommended for security)")
    print("2. Use SSH Password (Requires 'sshpass' tool)")
    auth_choice = get_user_input("Choose authentication method (1 or 2)", "1")

    ssh_key_path = None
    ssh_password = None

    if auth_choice == "1":
        ssh_key_path_input = get_user_input("Enter SSH Private Key Path (e.g., ~/.ssh/id_rsa)", "")
        ssh_key_path = ssh_key_path_input if ssh_key_path_input else None
        if not ssh_key_path:
            print("Warning: No SSH Private Key path provided. SSH will try agent or default keys. If it fails, you might need to use password option or ensure key is loaded.")
    elif auth_choice == "2":
        ssh_password = getpass.getpass("Enter SSH Password for Node VPS: ") # Securely get password
    else:
        print("Invalid authentication choice. Exiting.")
        sys.exit(1)

    print(f"\n--- Automating SSL Certificate Setup for Node: {node_domain} ({node_ip}) ---")
    print(f"Remnawave Compose Dir: {remnawave_compose_dir}")
    print(f"Panel Host Certs Dir: {panel_host_cert_base_path}")
    print(f"Container Certs Dir: {container_cert_base_path}")

    # 1. Copy certificates from Node VPS to Panel VPS
    panel_host_node_cert_path = copy_certs_from_node(node_user, node_ip, node_domain, panel_host_cert_base_path, ssh_key_path, ssh_password)

    # 2. Update docker-compose.yml with the new volume mount
    container_node_cert_path = update_docker_compose_volumes(docker_compose_file, node_domain, panel_host_node_cert_path, container_cert_base_path)

    # 3. Restart Docker Compose
    restart_docker_compose(remnawave_compose_dir)

    print("\n--- Automation Complete ---")
    print(f"SSL Certificate setup for {node_domain} is complete on Panel VPS.")
    print("Next Steps:")
    print("1. Log in to your Remnawave Panel (Web UI).")
    print(f"2. When configuring the Xray Inbound for {node_domain}, ensure you set the certificate paths as follows:")
    print(f"   \"keyFile\": \"{container_node_cert_path}/privkey.pem\",")
    print(f"   \"certificateFile\": \"{container_node_cert_path}/fullchain.pem\"")
    print("   (Note: Use .pem for both, as Let's Encrypt typically provides privkey.pem)")
    print("3. Push the updated configuration to your Xray Node.")
    print("\nGreat job, Squall! You're making things incredibly flexible and efficient!")
