# RKE2 Image Preparation Toolkit

Production-ready automation suite for deploying RKE2 Kubernetes clusters in air-gapped and restricted environments. Automatically discovers, downloads, and distributes all required container images to private registries with enterprise-grade security and operational best practices.

**Key Capabilities:**
- 🔍 Auto-discovery of latest stable RKE2 & CNI plugin releases
- 📦 Offline image download and packaging (65+ container images)
- 🚀 Private registry deployment and population
- 🔐 Secure authentication with multiple credential methods
- ✨ Automated dependency installation (curl, skopeo)
- 📊 Comprehensive logging and error handling

**Perfect for:** Air-gapped installations, compliance-restricted environments, edge deployments, and organizations requiring local image repositories.

---

A comprehensive automation suite for preparing, downloading, and distributing RKE2 (Rancher Kubernetes Engine 2) container images for air-gapped and private registry deployments.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Scripts](#scripts)
  - [rke2imageprep.sh](#rke2imageprepsh)
  - [registry/run-altregistry.sh](#registryrun-altregistrysh)
- [Usage Examples](#usage-examples)
- [Workflow Guide](#workflow-guide)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)
- [Contributing](#contributing)

## 🎯 Overview

This toolkit solves the challenge of deploying RKE2 Kubernetes clusters in restricted environments where direct internet access is limited or prohibited. It provides automated workflows for:

1. **Discovery**: Automatically fetch the latest stable RKE2 and CNI plugin releases from GitHub
2. **Download**: Pull all required container images using `skopeo` for offline storage
3. **Distribution**: Push images to private/alternative registries with authentication support
4. **Registry Setup**: Deploy a local Docker registry for image hosting

### Key Features

- ✅ **Automated Release Discovery**: Queries GitHub API for latest stable releases
- ✅ **Multi-Architecture Support**: Handles AMD64 images with multi-arch manifest support
- ✅ **Secure Credential Handling**: Multiple authentication methods (interactive, file-based)
- ✅ **Idempotent Operations**: Safe to run multiple times without side effects
- ✅ **Comprehensive Logging**: Detailed progress tracking and error reporting
- ✅ **Dependency Management**: Automatic dependency checking and installation guidance
- ✅ **Production-Ready**: Implements industry best practices for reliability and security

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     RKE2 Image Preparation Workflow             │
└─────────────────────────────────────────────────────────────────┘

1. DISCOVERY PHASE (rke2imageprep.sh --prep)
   ┌──────────────┐
   │ GitHub API   │
   │  - RKE2      │──────► Parse latest stable release version
   │  - CNI       │──────► Download image manifest (*.txt)
   └──────────────┘       │
                          ▼
                  ┌───────────────┐
                  │ Image List    │
                  │ (64+ images)  │
                  └───────────────┘

2. DOWNLOAD PHASE (rke2imageprep.sh --download)
   ┌────────────────┐
   │ Docker Hub     │
   │ (docker.io)    │──skopeo copy──► downloads/
   └────────────────┘                 │
                                      ├─ rancher_image1/
                                      ├─ rancher_image2/
                                      └─ ... (OCI format)

3. DISTRIBUTION PHASE (rke2imageprep.sh --push)
   ┌────────────────┐              ┌──────────────────┐
   │ downloads/     │─skopeo copy─►│ Private Registry │
   │ (OCI format)   │              │ (your-reg:5000)  │
   └────────────────┘              └──────────────────┘

4. REGISTRY SETUP (run-altregistry.sh)
   ┌────────────────┐
   │ Docker Engine  │──deploy──► altregistry container
   │                │            (port 8443)
   └────────────────┘
```

## 🔧 Prerequisites

### Required Software

| Tool | Purpose | Installation |
|------|---------|--------------|
| **bash** | Shell interpreter | Pre-installed on most Linux systems |
| **curl** | HTTP client for API calls | `apt install curl` or `yum install curl` |
| **skopeo** | Container image operations | `apt install skopeo` or `yum install skopeo` |
| **Docker** | Container runtime (for registry) | Auto-installed by `run-altregistry.sh` |

### System Requirements

- **Operating System**: Linux (Ubuntu, Debian, RHEL, CentOS, Fedora, Rocky, AlmaLinux)
- **Disk Space**: Minimum 50GB free (RKE2 images can be large)
- **Network**: Internet access for downloading images (download phase only)
- **Permissions**: sudo/root access for Docker installation and registry setup

### Optional Dependencies

- **grep with PCRE**: For JSON parsing (usually pre-installed)
- **base64**: For password file encoding (pre-installed)

## 📥 Installation

1. **Clone or download the repository**:
   ```bash
   git clone <repository-url>
   cd rke2iprep
   ```

2. **Make scripts executable**:
   ```bash
   chmod +x rke2imageprep.sh registry/run-altregistry.sh
   ```

3. **Install skopeo** (if not already installed):
   ```bash
   # Ubuntu/Debian
   sudo apt-get update
   sudo apt-get install -y skopeo

   # RHEL/CentOS/Fedora
   sudo dnf install -y skopeo
   ```

4. **Verify installation**:
   ```bash
   ./rke2imageprep.sh --help
   ```

## 📜 Scripts

### rke2imageprep.sh

**Purpose**: Main automation script for RKE2 image lifecycle management.

#### Functions

##### 1. `action_image_prep` (--prep)

**What it does**:
- Queries GitHub API for latest stable RKE2 release
- Downloads official image manifest from GitHub releases
- Fetches latest CNI plugins version
- Displays complete list of all OCI-compliant AMD64 images

**How it works**:
1. Makes HTTP GET request to `https://api.github.com/repos/rancher/rke2/releases/latest`
2. Parses JSON response to extract version tag (e.g., `v1.34.1+rke2r1`)
3. Downloads image list from `https://github.com/rancher/rke2/releases/download/{version}/rke2-images-all.linux-amd64.txt`
4. Repeats process for CNI plugins repository
5. Combines and displays all image references

**Output format**:
```
docker.io/rancher/hardened-kubernetes:v1.34.1-rke2r1-build20250910
docker.io/rancher/hardened-etcd:v3.6.4-k3s3-build20250908
...
```

**Use cases**:
- Planning air-gap deployments
- Version auditing and compliance
- Capacity planning for storage
- Pre-flight checks before downloads

---

##### 2. `action_image_download` (--download)

**What it does**:
- Downloads all RKE2 and CNI plugin images to local storage
- Uses `skopeo` for registry-independent image operations
- Stores images in OCI directory format for portability
- Tracks success/failure metrics

**How it works**:
1. Verifies `skopeo` is installed (fails fast if missing)
2. Creates download directory with proper permissions
3. Fetches image list (same as `--prep`)
4. Iterates through each image:
   - Transforms image name to filesystem-safe directory name
   - Executes `skopeo copy --override-arch amd64 docker://<image> dir:<path>`
   - Captures and logs results
5. Displays summary with success/failure counts

**Storage format**:
```
downloads/
├── rancher_hardened-kubernetes_v1.34.1-rke2r1-build20250910/
│   ├── manifest.json
│   ├── version
│   ├── <layer-sha256-1>
│   └── <layer-sha256-2>
├── rancher_hardened-etcd_v3.6.4-k3s3-build20250908/
│   └── ...
```

**Parameters**:
- `[DIR]` - Optional download directory (default: `./downloads`)

**Example**:
```bash
# Download to default location
./rke2imageprep.sh --download

# Download to custom location
./rke2imageprep.sh --download /mnt/large-disk/rke2-images
```

**Performance considerations**:
- Downloads are sequential (not parallelized)
- Each image can be 100MB - 2GB in size
- Total download size: ~15-30GB for full RKE2 release
- Estimated time: 30-120 minutes depending on bandwidth

---

##### 3. `action_image_push` (--push)

**What it does**:
- Pushes downloaded images to a private/alternative registry
- Supports authenticated and unauthenticated registries
- Preserves image namespace and tag structure
- Provides multiple credential input methods

**How it works**:
1. Validates required `--registry` parameter
2. Checks that download directory exists
3. Handles authentication:
   - **Interactive**: Prompts for username/password
   - **File-based**: Reads base64-encoded password from file
   - **No-auth**: Skips authentication for insecure registries
4. Re-fetches image list to ensure consistency
5. For each image:
   - Maps downloaded directory to original image name
   - Constructs target image reference
   - Executes `skopeo copy dir:<source> docker://<target>`
   - Logs success/failure
6. Displays push summary
7. **Generates RKE2 `registries.yaml` configuration file**:
   - Creates mirror configuration for docker.io and all registries (*)
   - Includes authentication section if credentials were provided
   - Outputs deployment instructions for RKE2 nodes

**Authentication flow**:
```
┌─────────────────┐
│ --no-auth?      │──Yes──► Skip authentication
└─────────────────┘
        │ No
        ▼
┌─────────────────┐
│ --password-file?│──Yes──► Read base64 file
└─────────────────┘
        │ No
        ▼
┌─────────────────┐
│ Interactive     │──► Prompt for credentials
│ Prompt          │    (password hidden)
└─────────────────┘
```

**Parameters**:
- `--registry <URL>` - **Required**. Target registry URL (e.g., `registry.example.com:5000`)
- `--no-auth` - Skip authentication (for insecure registries)
- `--password-file <path>` - Path to base64-encoded password file
- `--download-dir <path>` - Source directory (default: `./downloads`)

**Examples**:
```bash
# Push to unauthenticated registry
./rke2imageprep.sh --push --registry localhost:5000 --no-auth

# Push with interactive authentication
./rke2imageprep.sh --push --registry registry.company.com:443

# Push with password file
echo -n "my-secret-password" | base64 > /tmp/registry-pass.b64
./rke2imageprep.sh --push \
  --registry registry.company.com:443 \
  --password-file /tmp/registry-pass.b64

# Push from custom download directory
./rke2imageprep.sh --push \
  --registry registry.company.com:443 \
  --download-dir /mnt/external/rke2-images \
  --no-auth
```

**Output**:
After a successful push, the script generates `registries.yaml` in the current directory. This file must be deployed to `/etc/rancher/rke2/registries.yaml` on all RKE2 nodes (both servers and agents) before starting or restarting RKE2.

Example `registries.yaml` (with authentication):
```yaml
# RKE2 Private Registry Configuration
# Generated by rke2imageprep.sh
# Target Registry: registry.company.com:5000

mirrors:
  docker.io:
    endpoint:
      - "https://registry.company.com:5000"
  "*":
    endpoint:
      - "https://registry.company.com:5000"

configs:
  "registry.company.com:5000":
    auth:
      username: admin
      password: <YOUR_PASSWORD_HERE>
```

**Deployment Steps**:
```bash
# 1. Edit registries.yaml and add your password
vim registries.yaml

# 2. Copy to RKE2 configuration directory on all nodes
sudo cp registries.yaml /etc/rancher/rke2/registries.yaml

# 3. Set secure permissions
sudo chmod 600 /etc/rancher/rke2/registries.yaml

# 4. Restart RKE2 service
sudo systemctl restart rke2-server  # or rke2-agent for agent nodes
```

**Security notes**:
- Passwords are transmitted via command-line arguments (visible in `ps` output momentarily)
- For production: Use orchestration tools with secret management
- Base64 encoding is NOT encryption - protect password files appropriately
- Consider using registry tokens instead of passwords
- Always set `registries.yaml` file permissions to 600 to protect credentials

---

### registry/run-altregistry.sh

**Purpose**: Automated deployment of a private Docker registry for local image hosting.

#### What it does

1. **Docker Installation** (if needed):
   - Detects operating system automatically
   - Prompts user for installation confirmation
   - Adds official Docker repositories
   - Installs Docker CE and related components
   - Starts and enables Docker daemon

2. **Registry Deployment**:
   - Creates persistent data directory
   - Pulls official Docker registry:2 image
   - Removes existing registry container (if present)
   - Deploys new registry container with production settings
   - Configures automatic restart on failure/reboot

#### How it works

**Step-by-step execution**:

```
1. Dependency Check
   ├─ Docker installed? ──No──► install_docker()
   └─ Yes ──────────────────────► Continue

2. Preparation
   ├─ Create /opt/altregistry/data
   └─ Pull registry:2 image

3. Container Lifecycle
   ├─ Check for existing container
   ├─ Stop and remove if exists
   └─ Deploy new container

4. Configuration
   ├─ Name: altregistry
   ├─ Port: 8443 (external) → 5000 (internal)
   ├─ Volume: /opt/altregistry/data
   └─ Restart: always
```

**Container configuration**:
```bash
docker run -d \
  --name altregistry \           # Container name for management
  --restart=always \              # Auto-restart on failure/reboot
  -p 8443:5000 \                  # Port mapping (host:container)
  -v /opt/altregistry/data:/var/lib/registry \  # Persistent storage
  -e REGISTRY_HTTP_ADDR=0.0.0.0:5000 \          # Listen address
  registry:2                      # Official registry image
```

#### Configuration Variables

| Variable | Default Value | Purpose |
|----------|---------------|---------|
| `REGISTRY_IMAGE` | `registry:2` | Docker registry version to deploy |
| `REGISTRY_NAME` | `altregistry` | Container name for management |
| `REGISTRY_HOST` | `altregistry.dev.kube` | DNS hostname for client access |
| `REGISTRY_PORT` | `8443` | External port for registry API |
| `REGISTRY_DATA_DIR` | `/opt/altregistry/data` | Persistent storage location |

**Customization**:
Edit these variables at the top of the script before execution:
```bash
# Example: Change port and data directory
REGISTRY_PORT="5000"
REGISTRY_DATA_DIR="/data/registry"
```

#### Post-Deployment Setup

**1. DNS/Hosts Configuration**:
```bash
# Add to /etc/hosts on client machines
echo "192.168.1.100  altregistry.dev.kube" | sudo tee -a /etc/hosts
```

**2. Docker Daemon Configuration** (for insecure registry):
```bash
# /etc/docker/daemon.json
{
  "insecure-registries": ["altregistry.dev.kube:8443"]
}

# Restart Docker
sudo systemctl restart docker
```

**3. Verify Registry Access**:
```bash
# Test registry API
curl http://altregistry.dev.kube:8443/v2/_catalog

# Push test image
docker tag alpine:latest altregistry.dev.kube:8443/alpine:test
docker push altregistry.dev.kube:8443/alpine:test
```

#### Production Enhancements

The script provides a basic HTTP registry. For production use, consider:

**1. TLS Encryption**:
```bash
# Option A: Reverse proxy (nginx/traefik)
# Option B: Native TLS
docker run -d \
  --name altregistry \
  --restart=always \
  -p 443:5000 \
  -v /opt/altregistry/data:/var/lib/registry \
  -v /opt/altregistry/certs:/certs \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
  registry:2
```

**2. Authentication**:
```bash
# Create htpasswd file
htpasswd -Bc /opt/altregistry/auth/htpasswd admin

# Run with auth
docker run -d \
  --name altregistry \
  --restart=always \
  -p 8443:5000 \
  -v /opt/altregistry/data:/var/lib/registry \
  -v /opt/altregistry/auth:/auth \
  -e REGISTRY_AUTH=htpasswd \
  -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" \
  -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
  registry:2
```

**3. Storage Backend**:
```bash
# S3-compatible storage
-e REGISTRY_STORAGE=s3 \
-e REGISTRY_STORAGE_S3_REGION=us-east-1 \
-e REGISTRY_STORAGE_S3_BUCKET=my-registry-bucket \
-e REGISTRY_STORAGE_S3_ACCESSKEY=AKIA... \
-e REGISTRY_STORAGE_S3_SECRETKEY=...
```

**4. Garbage Collection**:
```bash
# Schedule periodic cleanup
0 2 * * 0 docker exec altregistry bin/registry garbage-collect /etc/docker/registry/config.yml
```

## 💡 Usage Examples

### Complete Air-Gap Deployment Workflow

```bash
# On internet-connected machine:

# 1. Discover latest images
./rke2imageprep.sh --prep > rke2-images-$(date +%Y%m%d).txt

# 2. Download all images
./rke2imageprep.sh --download /mnt/external/rke2-images

# 3. Transfer download directory to air-gapped environment
# (USB drive, secure file transfer, etc.)

# On air-gapped machine:

# 4. Deploy private registry
./registry/run-altregistry.sh

# 5. Push images to local registry
./rke2imageprep.sh --push \
  --registry altregistry.dev.kube:8443 \
  --download-dir /mnt/external/rke2-images \
  --no-auth

# 6. Deploy registries.yaml to RKE2 nodes
# registries.yaml was automatically generated in step 5
sudo cp registries.yaml /etc/rancher/rke2/registries.yaml
sudo chmod 600 /etc/rancher/rke2/registries.yaml

# 7. Start RKE2
sudo systemctl enable rke2-server
sudo systemctl start rke2-server
```

### Quick Start (Local Testing)

```bash
# 1. Set up local registry
./registry/run-altregistry.sh

# 2. Download and push in one workflow
./rke2imageprep.sh --download && \
./rke2imageprep.sh --push --registry localhost:8443 --no-auth
```

### Selective Image Management

```bash
# Download specific version (modify script)
VERSION="v1.33.5+rke2r1"
skopeo copy docker://rancher/hardened-kubernetes:${VERSION} dir:./downloads/kubernetes

# Verify image integrity
skopeo inspect dir:./downloads/kubernetes
```

## 🔄 Workflow Guide

### Scenario 1: Initial Air-Gap Setup

**Prerequisites**: Internet-connected staging machine + air-gapped production environment

```bash
# === STAGING MACHINE (Internet access) ===

# Step 1: Prepare workspace
mkdir -p ~/rke2-airgap
cd ~/rke2-airgap
./rke2imageprep.sh --prep | tee image-list.txt

# Step 2: Download images
./rke2imageprep.sh --download ./images

# Step 3: Package for transfer
tar -czf rke2-images-$(date +%Y%m%d).tar.gz images/
# Transfer tar file to production environment

# === PRODUCTION MACHINE (Air-gapped) ===

# Step 4: Extract images
tar -xzf rke2-images-*.tar.gz

# Step 5: Deploy registry
./registry/run-altregistry.sh

# Step 6: Populate registry
./rke2imageprep.sh --push \
  --registry registry.internal.company:5000 \
  --download-dir ./images \
  --password-file /secure/registry-creds.b64

# Step 7: Verify
curl http://registry.internal.company:5000/v2/_catalog
```

### Scenario 2: Registry Migration

**Goal**: Move images from one registry to another

```bash
# Method 1: Via local storage
./rke2imageprep.sh --download
./rke2imageprep.sh --push --registry new-registry.com:443

# Method 2: Direct registry-to-registry (using skopeo)
skopeo copy \
  --src-creds old-user:old-pass \
  --dest-creds new-user:new-pass \
  docker://old-registry.com/rancher/image:tag \
  docker://new-registry.com/rancher/image:tag
```

### Scenario 3: Periodic Updates

**Goal**: Keep private registry synchronized with latest RKE2 releases

```bash
#!/bin/bash
# cron job: 0 2 * * 0 (weekly Sunday 2 AM)

WORKDIR=/opt/rke2-sync
REGISTRY=registry.company.com:443

cd $WORKDIR

# Download latest images
./rke2imageprep.sh --download ./images-$(date +%Y%m%d)

# Push to registry
./rke2imageprep.sh --push \
  --registry $REGISTRY \
  --download-dir ./images-$(date +%Y%m%d) \
  --password-file /secure/registry-creds.b64

# Cleanup old downloads (keep last 3)
ls -t | grep ^images- | tail -n +4 | xargs rm -rf

# Send notification
echo "RKE2 registry sync completed" | mail -s "Registry Update" ops@company.com
```

## 🏆 Best Practices

### Security

1. **Credential Management**:
   - Never commit passwords to version control
   - Use environment variables or secure vaults
   - Rotate credentials regularly
   - Prefer token-based authentication over passwords

2. **Network Security**:
   - Use TLS for registry communication
   - Implement firewall rules to restrict registry access
   - Use VPN or private networks for sensitive deployments
   - Enable registry authentication in production

3. **Image Integrity**:
   - Verify image signatures when possible
   - Use content-addressable storage (SHA256 digests)
   - Implement vulnerability scanning
   - Track image provenance

### Operational

1. **Storage Management**:
   - Monitor disk usage regularly
   - Implement retention policies
   - Use garbage collection for unused layers
   - Consider object storage for scalability

2. **Monitoring**:
   - Track registry health and performance
   - Log all push/pull operations
   - Set up alerts for failures
   - Monitor bandwidth usage

3. **Backup and Recovery**:
   - Regular backups of `/opt/altregistry/data`
   - Test restore procedures
   - Document recovery processes
   - Version control configuration files

4. **Documentation**:
   - Maintain image inventory
   - Document custom images and modifications
   - Track deployment history
   - Keep runbooks updated

### Performance

1. **Download Optimization**:
   - Use high-bandwidth network connections
   - Consider parallel downloads (modify rke2imageprep.sh)
   - Enable compression where supported
   - Use local mirrors when available

2. **Registry Tuning**:
   - Allocate sufficient disk I/O
   - Use SSD storage for better performance
   - Configure appropriate cache sizes
   - Monitor and adjust resource limits

## 🔍 Troubleshooting

### Common Issues

#### 1. "skopeo: command not found"

**Cause**: Skopeo is not installed

**Solution**:
```bash
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y skopeo

# RHEL/CentOS
sudo dnf install -y skopeo
```

#### 2. "manifest unknown" errors during download

**Cause**: Image tag doesn't exist or multi-arch manifest issue

**Solution**:
```bash
# Verify image exists
skopeo inspect docker://docker.io/rancher/image:tag

# Check available tags
skopeo list-tags docker://docker.io/rancher/image
```

#### 3. Authentication failures during push

**Cause**: Invalid credentials or registry not configured for auth

**Solution**:
```bash
# Test credentials manually
skopeo login registry.company.com:443

# Verify password file encoding
base64 -d /path/to/password-file  # Should output readable password

# Check registry logs
docker logs altregistry
```

#### 4. "connection refused" to registry

**Cause**: Registry not running or firewall blocking

**Solution**:
```bash
# Check registry status
docker ps | grep altregistry

# Test port connectivity
nc -zv altregistry.dev.kube 8443

# Check firewall
sudo firewall-cmd --list-all  # RHEL/CentOS
sudo ufw status                # Ubuntu
```

#### 5. Disk space exhaustion

**Cause**: Insufficient storage for images

**Solution**:
```bash
# Check available space
df -h

# Move to larger filesystem
mv downloads/ /mnt/large-disk/
./rke2imageprep.sh --download /mnt/large-disk/downloads

# Cleanup old downloads
rm -rf ./downloads-old/
```

### Debug Mode

Enable verbose logging:
```bash
# Add to script
set -x  # Print commands before execution

# Run with debug output
bash -x ./rke2imageprep.sh --prep 2>&1 | tee debug.log
```

### Getting Help

1. **Check logs**:
   - Script output for error messages
   - Docker logs: `docker logs altregistry`
   - System logs: `/var/log/syslog` or `journalctl`

2. **Verify prerequisites**:
   ```bash
   command -v curl && echo "curl: OK"
   command -v skopeo && echo "skopeo: OK"
   command -v docker && echo "docker: OK"
   ```

3. **Test connectivity**:
   ```bash
   curl -I https://api.github.com
   ping docker.io
   ```

## 🔒 Security Considerations

### Threat Model

**Assets to protect**:
- Container images (may contain proprietary code)
- Registry credentials
- Network traffic between components

**Potential threats**:
- Man-in-the-middle attacks (unencrypted HTTP)
- Unauthorized access to registry
- Image tampering or injection
- Credential exposure

### Mitigation Strategies

1. **Use TLS everywhere**:
   - Registry API (HTTPS)
   - Image pulls/pushes
   - Certificate validation

2. **Implement defense in depth**:
   - Network segmentation
   - Firewall rules
   - Authentication + authorization
   - Audit logging

3. **Follow principle of least privilege**:
   - Dedicated service accounts
   - Role-based access control
   - Regular permission audits

4. **Secure the supply chain**:
   - Verify image signatures
   - Scan for vulnerabilities
   - Use trusted base images
   - Track dependencies

### Compliance

**Considerations for regulated environments**:
- Maintain audit trail of all image operations
- Implement change management processes
- Regular security assessments
- Data residency requirements
- Encryption at rest and in transit

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. **Code Style**:
   - Follow existing bash conventions
   - Use descriptive variable names
   - Add comments for complex logic
   - Include error handling

2. **Testing**:
   - Test on multiple OS distributions
   - Verify backward compatibility
   - Document test procedures

3. **Documentation**:
   - Update README for new features
   - Add inline comments
   - Provide usage examples

4. **Submit Pull Requests**:
   - Clear description of changes
   - Reference related issues
   - Include test results

## 📄 License

[Specify your license here]

## 📞 Support

For issues and questions:
- GitHub Issues: [repository-url]/issues
- Email: [support-email]
- Documentation: [docs-url]

---

**Version**: 1.0.0  
**Last Updated**: 2025-11-14  
**Maintained by**: Ron Cantrell
