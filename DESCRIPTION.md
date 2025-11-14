# Repository Description

## RKE2 Image Preparation Toolkit

Production-ready automation suite for deploying RKE2 Kubernetes clusters in air-gapped and restricted environments. Automatically discovers, downloads, and distributes all required container images to private registries with enterprise-grade security and operational best practices.

### Key Capabilities

- 🔍 **Auto-discovery** of latest stable RKE2 & CNI plugin releases
- 📦 **Offline image download** and packaging (65+ container images)
- 🚀 **Private registry deployment** and population
- 🔐 **Secure authentication** with multiple credential methods
- ✨ **Automated dependency installation** (curl, skopeo)
- 📊 **Comprehensive logging** and error handling

### Perfect For

- **Air-gapped installations**: Environments without direct internet access
- **Compliance-restricted environments**: Organizations with strict security policies
- **Edge deployments**: Remote locations with limited connectivity
- **Local image repositories**: Organizations requiring internal image hosting

### What This Toolkit Provides

1. **rke2imageprep.sh**: Main automation script for image lifecycle management
   - Discover latest RKE2 and CNI plugin releases
   - Download all required container images
   - Push images to private registries

2. **registry/run-altregistry.sh**: Automated Docker registry deployment
   - One-command registry setup
   - Automated Docker installation
   - Production-ready configuration

### Use Cases

- **Initial air-gap setup**: Prepare images on internet-connected machine, transfer to isolated environment
- **Regular updates**: Keep private registries synchronized with latest RKE2 releases
- **Multi-site deployments**: Replicate images across multiple locations
- **Disaster recovery**: Maintain offline image archives for emergency restoration
- **Development/testing**: Local registry for faster iteration cycles

### Technical Highlights

- **Industry best practices**: Comprehensive error handling, logging, and security
- **Idempotent operations**: Safe to run multiple times
- **OS compatibility**: Ubuntu, Debian, RHEL, CentOS, Fedora, Rocky Linux, AlmaLinux
- **Dependency automation**: Automatically installs missing tools with user consent
- **OCI compliance**: Uses skopeo for registry-independent operations
- **Multi-arch support**: Handles AMD64 images with proper architecture selection

### Quick Start

```bash
# Clone repository
git clone <repository-url>
cd rke2iprep

# Make scripts executable
chmod +x rke2imageprep.sh registry/run-altregistry.sh

# View latest RKE2 images
./rke2imageprep.sh --prep

# Download images for offline use
./rke2imageprep.sh --download

# Deploy local registry
./registry/run-altregistry.sh

# Push images to registry
./rke2imageprep.sh --push --registry localhost:8443 --no-auth
```

### Documentation

See [README.md](README.md) for comprehensive documentation including:
- Detailed architecture diagrams
- Complete workflow guides
- Security best practices
- Troubleshooting guides
- Production deployment examples

### Contributing

This toolkit is designed for production use in enterprise environments. Contributions are welcome to improve functionality, add support for additional platforms, or enhance documentation.

### License

[Specify your license here]

---

**Version**: 1.0.0  
**Last Updated**: 2025-11-14  
**Maintained by**: DevOps Team
