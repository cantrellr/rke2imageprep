#!/usr/bin/env bash
#
# Alternative Docker Registry Setup Script
# ========================================
# Purpose: Automated deployment of a private Docker registry for air-gapped
#          or restricted environments requiring local image hosting
#
# Author: Ron Cantrell
# Version: 1.0.0
# Last Modified: 2025-11-14
#
# Dependencies:
#   - Docker: Container runtime for registry deployment
#   - curl/wget: For downloading Docker installation packages
#
# Best Practices Implemented:
#   - Idempotent operations (safe to run multiple times)
#   - Automatic dependency installation with user confirmation
#   - Container lifecycle management (cleanup before creation)
#   - Persistent data storage with volume mounts
#   - Comprehensive error handling and user feedback
#
# Security Considerations:
#   - Default deployment is HTTP-only (suitable for internal networks)
#   - For production: Add TLS termination via reverse proxy
#   - Consider implementing authentication/authorization
#   - Restrict network access via firewall rules

# Bash strict mode for better error handling
# -e: Exit on error
# -u: Exit on undefined variable
# -o pipefail: Catch errors in pipes
# Best Practice: Fail fast to prevent cascading failures
set -euo pipefail

#=============================================================================
# Configuration Variables
# Best Practice: Centralize configuration for easy customization
#=============================================================================
REGISTRY_IMAGE="registry:2"                    # Official Docker registry image
REGISTRY_NAME="altregistry"                    # Container name for management
REGISTRY_HOST="altregistry.dev.kube"           # DNS hostname for registry access
REGISTRY_PORT="8443"                           # External port mapping
REGISTRY_DATA_DIR="/opt/altregistry/data"      # Persistent storage location

#=============================================================================
# Function: install_docker
# Description: Automated Docker installation with OS detection and user consent
# Best Practice: Always prompt before system-level modifications
# Supported OS: Ubuntu, Debian, RHEL, CentOS, Fedora, Rocky Linux, AlmaLinux
#=============================================================================
install_docker() {
    echo "[*] Docker is not installed."
    echo ""
    
    # Interactive user confirmation before installation
    # Best Practice: Require explicit consent for system changes
    # -n 1: Read single character, -r: Don't interpret backslashes
    read -p "Would you like to install Docker now? (y/n): " -n 1 -r
    echo ""
    
    # Validate user response using regex pattern matching
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "[!] Docker installation cancelled. Please install Docker manually and rerun."
        exit 1
    fi
    
    echo "[*] Installing Docker..."
    
    # OS detection using /etc/os-release (standard across modern Linux distributions)
    # Best Practice: Use standard files rather than parsing command output
    if [[ -f /etc/os-release ]]; then
        # Source the file to import variables like ID and VERSION_CODENAME
        . /etc/os-release
        OS=$ID
    else
        echo "[!] Cannot detect OS. Please install Docker manually."
        exit 1
    fi
    
    # OS-specific installation procedures
    # Best Practice: Use official Docker repositories for security and updates
    case "$OS" in
        ubuntu|debian)
            echo "[*] Detected Debian/Ubuntu - installing Docker via apt..."
            
            # Update package index for latest package information
            sudo apt-get update
            
            # Install prerequisite packages for HTTPS repository access
            sudo apt-get install -y ca-certificates curl gnupg
            
            # Create directory for APT keyrings with secure permissions
            sudo install -m 0755 -d /etc/apt/keyrings
            
            # Add Docker's official GPG key for package verification
            # Best Practice: Always verify package signatures
            curl -fsSL https://download.docker.com/linux/${OS}/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            
            # Add Docker repository to APT sources
            # Uses architecture-specific packages and distribution codename
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS} \
              $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
              sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # Refresh package index with new repository
            sudo apt-get update
            
            # Install Docker components:
            # - docker-ce: Core engine
            # - docker-ce-cli: Command-line interface
            # - containerd.io: Container runtime
            # - docker-buildx-plugin: Extended build capabilities
            # - docker-compose-plugin: Multi-container orchestration
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        rhel|centos|fedora|rocky|almalinux)
            echo "[*] Detected RHEL/CentOS/Fedora - installing Docker via dnf/yum..."
            
            # Install yum-utils for repository management
            sudo yum install -y yum-utils
            
            # Add Docker repository configuration
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            
            # Install Docker components
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            
            # Start Docker daemon immediately
            sudo systemctl start docker
            
            # Enable Docker to start on boot
            # Best Practice: Ensure services survive reboots
            sudo systemctl enable docker
            ;;
        *)
            # Unsupported OS fallback with helpful guidance
            echo "[!] Unsupported OS: $OS"
            echo "[!] Please install Docker manually from https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac
    
    # Post-installation verification
    # Best Practice: Verify installation success before proceeding
    if ! command -v docker >/dev/null 2>&1; then
        echo "[!] Docker installation failed. Please install manually."
        exit 1
    fi
    
    echo "[*] Docker installed successfully!"
    docker --version
    echo ""
}

#=============================================================================
# Main Execution Block
#=============================================================================

# Step 1: Verify Docker availability
echo "[*] Verifying Docker is installed..."
if ! command -v docker >/dev/null 2>&1; then
  # Docker not found - trigger installation workflow
  install_docker
fi

# Step 2: Prepare persistent data directory
echo "[*] Creating data directory at ${REGISTRY_DATA_DIR} (if needed)..."
# Best Practice: mkdir -p creates parents and succeeds if directory exists
mkdir -p "${REGISTRY_DATA_DIR}"

# Step 3: Pull latest registry image from Docker Hub
echo "[*] Pulling latest registry image: ${REGISTRY_IMAGE}..."
# Best Practice: Always pull latest image to get security updates
docker pull "${REGISTRY_IMAGE}"

# Step 4: Clean up existing registry container (if any)
# Best Practice: Idempotent deployment - remove old container before creating new one
if docker ps -a --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}\$"; then
  echo "[*] Existing container '${REGISTRY_NAME}' detected. Stopping and removing..."
  # Stop gracefully (SIGTERM), fall back to force if needed
  docker stop "${REGISTRY_NAME}" >/dev/null 2>&1 || true
  # Remove container to free up name and resources
  docker rm "${REGISTRY_NAME}" >/dev/null 2>&1 || true
fi

# Step 5: Launch new registry container
echo "[*] Starting registry container '${REGISTRY_NAME}' on ${REGISTRY_HOST}:${REGISTRY_PORT}..."

# Container deployment with production-ready settings
docker run -d \
  --name "${REGISTRY_NAME}" \
  --restart=always \
  -p "${REGISTRY_PORT}:5000" \
  -v "${REGISTRY_DATA_DIR}:/var/lib/registry" \
  -e REGISTRY_HTTP_ADDR="0.0.0.0:5000" \
  "${REGISTRY_IMAGE}"
# Flags explained:
# -d: Detached mode (run in background)
# --name: Assign friendly name for management
# --restart=always: Auto-restart on failure or reboot (Best Practice for services)
# -p: Port mapping (host:container)
# -v: Volume mount for persistent storage (survives container recreation)
# -e: Environment variable for registry configuration

# Step 6: Display deployment summary and configuration guidance
echo
echo "[*] Docker registry is starting."
echo "    Container name : ${REGISTRY_NAME}"
echo "    Image          : ${REGISTRY_IMAGE}"
echo "    Data dir       : ${REGISTRY_DATA_DIR}"
echo "    URL            : ${REGISTRY_HOST}:${REGISTRY_PORT}"
echo
echo "NOTE:"
echo " - Make sure DNS or /etc/hosts maps '${REGISTRY_HOST}' to this host's IP."
echo " - This is plain HTTP on the container side; port ${REGISTRY_PORT} is mapped directly."
echo " - For TLS, front this with a reverse proxy or configure REGISTRY_HTTP_TLS_* env vars."
echo
echo "Best Practices for Production:"
echo " 1. Add TLS encryption (use nginx/traefik reverse proxy or native TLS)"
echo " 2. Enable authentication (htpasswd or token-based)"
echo " 3. Configure firewall rules to restrict access"
echo " 4. Set up regular backups of ${REGISTRY_DATA_DIR}"
echo " 5. Monitor disk usage and implement garbage collection"
echo " 6. Consider using external storage (S3, Azure Blob) for scalability"
