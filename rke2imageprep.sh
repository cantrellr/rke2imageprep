#!/bin/bash
#
# RKE2 Image Preparation and Management Script
# ===========================================
# Purpose: Automate the preparation, download, and distribution of RKE2 container images
#          for air-gapped or private registry deployments
#
# Author: Ron Cantrell
# Version: 1.0.0
# Last Modified: 2025-11-14
#
# Dependencies:
#   - curl: For API calls and file downloads
#   - skopeo: For container image operations (download/push)
#   - grep with PCRE support: For JSON parsing
#
# Best Practices Implemented:
#   - Fail-fast error handling with proper exit codes
#   - Secure credential handling (no plaintext passwords in scripts)
#   - Idempotent operations (can be run multiple times safely)
#   - Comprehensive logging and progress reporting
#   - Temporary file cleanup in all execution paths
#   - Input validation and dependency checking

#=============================================================================
# Function: action_image_prep
# Description: Discovers and displays the latest stable RKE2 and CNI plugin
#              container images for AMD64 architecture
# Parameters: None
# Returns: 0 on success, 1 on failure
# Usage: action_image_prep
#=============================================================================

#=============================================================================
# Function: install_dependencies
# Description: Checks for and installs missing dependencies (curl, skopeo)
# Best Practice: Automated dependency management with user consent
#=============================================================================
install_dependencies() {
    local missing_deps=()
    local need_curl=false
    local need_skopeo=false
    
    # Check for curl
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
        need_curl=true
    fi
    
    # Check for skopeo
    if ! command -v skopeo &> /dev/null; then
        missing_deps+=("skopeo")
        need_skopeo=true
    fi
    
    # Exit if all dependencies are satisfied
    if [ ${#missing_deps[@]} -eq 0 ]; then
        return 0
    fi
    
    # Display missing dependencies
    echo "Missing dependencies detected: ${missing_deps[*]}"
    echo ""
    
    # Prompt for installation
    read -p "Would you like to install missing dependencies now? (y/n): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled. Please install dependencies manually:"
        [ "$need_curl" = true ] && echo "  - curl"
        [ "$need_skopeo" = true ] && echo "  - skopeo"
        return 1
    fi
    
    # Detect OS for package manager selection
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
    else
        echo "Error: Cannot detect OS. Please install dependencies manually."
        return 1
    fi
    
    echo "Installing dependencies..."
    
    # Install based on OS
    case "$OS" in
        ubuntu|debian)
            echo "Detected Debian/Ubuntu - using apt..."
            sudo apt-get update
            [ "$need_curl" = true ] && sudo apt-get install -y curl
            [ "$need_skopeo" = true ] && sudo apt-get install -y skopeo
            ;;
        rhel|centos|fedora|rocky|almalinux)
            echo "Detected RHEL/CentOS/Fedora - using dnf/yum..."
            [ "$need_curl" = true ] && sudo dnf install -y curl || sudo yum install -y curl
            [ "$need_skopeo" = true ] && sudo dnf install -y skopeo || sudo yum install -y skopeo
            ;;
        *)
            echo "Error: Unsupported OS: $OS"
            echo "Please install dependencies manually:"
            [ "$need_curl" = true ] && echo "  - curl"
            [ "$need_skopeo" = true ] && echo "  - skopeo"
            return 1
            ;;
    esac
    
    # Verify installation
    local install_failed=false
    if [ "$need_curl" = true ] && ! command -v curl &> /dev/null; then
        echo "Error: curl installation failed"
        install_failed=true
    fi
    if [ "$need_skopeo" = true ] && ! command -v skopeo &> /dev/null; then
        echo "Error: skopeo installation failed"
        install_failed=true
    fi
    
    if [ "$install_failed" = true ]; then
        return 1
    fi
    
    echo "Dependencies installed successfully!"
    echo ""
    return 0
}

action_image_prep() {
    # Check and install dependencies if needed
    if ! install_dependencies; then
        echo "Error: Required dependencies not available"
        return 1
    fi
    
    # API endpoints for fetching latest release information
    local GITHUB_API="https://api.github.com/repos/rancher/rke2/releases/latest"
    
    # Create secure temporary directory with restricted permissions (700)
    # Best Practice: Use mktemp for race-condition-free temp file creation
    local TEMP_DIR=$(mktemp -d)
    
    echo "Fetching latest stable RKE2 release information..."
    
    # Query GitHub API for latest release metadata
    # Best Practice: Silent curl (-s) prevents progress bar clutter in logs
    local release_info=$(curl -s "$GITHUB_API")
    
    # Extract version tag from JSON response using PCRE regex
    # Best Practice: Validate API responses before proceeding
    local version=$(echo "$release_info" | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
    
    # Error handling: Exit gracefully if API call fails or returns unexpected data
    if [ -z "$version" ]; then
        echo "Error: Could not determine latest RKE2 version"
        # Best Practice: Always cleanup temporary resources on error paths
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    echo "Latest stable RKE2 version: $version"
    echo ""
    
    # Construct download URL for official RKE2 image manifest
    # Note: AMD64 is the most common production architecture
    local images_url="https://github.com/rancher/rke2/releases/download/${version}/rke2-images-all.linux-amd64.txt"
    
    echo "Downloading AMD64 images list from:"
    echo "$images_url"
    echo ""
    
    # Download official image list from GitHub releases
    # Best Practice: Use -L to follow redirects, -s for silent mode
    local images_file="${TEMP_DIR}/rke2-images-all.linux-amd64.txt"
    if ! curl -sSL -o "$images_file" "$images_url"; then
        echo "Error: Failed to download images list"
        # Cleanup temporary directory on failure
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Display all OCI-compliant container images for the release
    # These images include Kubernetes components, networking, storage, and monitoring
    echo "=========================================="
    echo "OCI Compliant AMD64 Images for RKE2 $version"
    echo "=========================================="
    echo ""
    
    # Output full image list with registry paths and version tags
    cat "$images_file"
    
    echo ""
    echo "=========================================="
    echo "Total images: $(wc -l < "$images_file")"
    echo "=========================================="
    echo ""
    
    # Fetch CNI (Container Network Interface) plugins separately
    # CNI plugins are maintained in a separate repository with different release cycles
    local CNI_GITHUB_API="https://api.github.com/repos/rancher/image-build-cni-plugins/releases/latest"
    
    echo "Fetching latest stable CNI plugins release information..."
    
    # Query CNI plugins repository for latest stable release
    local cni_release_info=$(curl -s "$CNI_GITHUB_API")
    
    # Parse version tag from JSON response
    local cni_version=$(echo "$cni_release_info" | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
    
    # Validate CNI version extraction
    if [ -z "$cni_version" ]; then
        echo "Error: Could not determine latest CNI plugins version"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    echo "Latest stable CNI plugins version: $cni_version"
    echo ""
    
    echo "=========================================="
    echo "OCI Compliant AMD64 Images for CNI Plugins $cni_version"
    echo "=========================================="
    echo ""
    # CNI plugins image uses multi-arch manifest (no -amd64 suffix needed)
    # Best Practice: Let skopeo's --override-arch handle architecture selection
    echo "docker.io/rancher/hardened-cni-plugins:$cni_version"
    echo ""
    echo "=========================================="
    echo "Total CNI plugin images: 1"
    echo "=========================================="
    
    # Cleanup: Remove temporary directory and all contents
    # Best Practice: Always cleanup resources to prevent disk space exhaustion
    rm -rf "$TEMP_DIR"
}

#=============================================================================
# Function: action_image_download
# Description: Downloads all RKE2 and CNI plugin images for offline use
#              using skopeo to preserve OCI format and multi-arch support
# Parameters:
#   $1 - Download directory path (optional, default: ./downloads)
# Returns: 0 if all downloads succeed, 1 if any failures occur
# Usage: action_image_download [/path/to/downloads]
#=============================================================================

action_image_download() {
    # Check and install dependencies if needed
    if ! install_dependencies; then
        echo "Error: Required dependencies not available"
        return 1
    fi
    
    # API endpoints for release information
    local GITHUB_API="https://api.github.com/repos/rancher/rke2/releases/latest"
    local CNI_GITHUB_API="https://api.github.com/repos/rancher/image-build-cni-plugins/releases/latest"
    
    # Use provided directory or default to ./downloads
    # Best Practice: Provide sensible defaults while allowing customization
    local DOWNLOADS_DIR="${1:-./downloads}"
    local TEMP_DIR=$(mktemp -d)
    
    # Create downloads directory with parents if needed
    # Best Practice: mkdir -p is idempotent and won't fail if directory exists
    mkdir -p "$DOWNLOADS_DIR"
    
    echo "=========================================="
    echo "Image Download Process Started"
    echo "Download directory: $DOWNLOADS_DIR"
    echo "=========================================="
    echo ""
    
    # Fetch RKE2 release metadata from GitHub API
    echo "Fetching latest stable RKE2 release information..."
    local release_info=$(curl -s "$GITHUB_API")
    local version=$(echo "$release_info" | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
    
    # Validate version extraction
    if [ -z "$version" ]; then
        echo "Error: Could not determine latest RKE2 version"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    echo "Latest stable RKE2 version: $version"
    
    # Download official image manifest from GitHub releases
    local images_url="https://github.com/rancher/rke2/releases/download/${version}/rke2-images-all.linux-amd64.txt"
    local images_file="${TEMP_DIR}/rke2-images-all.linux-amd64.txt"
    
    if ! curl -sSL -o "$images_file" "$images_url"; then
        echo "Error: Failed to download RKE2 images list"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Fetch CNI plugins version
    echo "Fetching latest stable CNI plugins release information..."
    local cni_release_info=$(curl -s "$CNI_GITHUB_API")
    local cni_version=$(echo "$cni_release_info" | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
    
    if [ -z "$cni_version" ]; then
        echo "Error: Could not determine latest CNI plugins version"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    echo "Latest stable CNI plugins version: $cni_version"
    echo ""
    
    # Combine RKE2 images and CNI plugins into single manifest
    # Best Practice: Single consolidated list simplifies iteration logic
    local combined_images="${TEMP_DIR}/all-images.txt"
    cat "$images_file" > "$combined_images"
    echo "docker.io/rancher/hardened-cni-plugins:$cni_version" >> "$combined_images"
    
    local total_images=$(wc -l < "$combined_images")
    echo "Total images to download: $total_images"
    echo ""
    
    # Initialize counters for success/failure tracking
    # Best Practice: Track metrics for reporting and troubleshooting
    local count=0
    local success=0
    local failed=0
    
    # Process each image in the manifest
    # Best Practice: Use while+read for proper handling of whitespace in filenames
    while IFS= read -r image; do
        count=$((count + 1))
        
        # Skip empty lines to handle trailing newlines gracefully
        [[ -z "$image" ]] && continue
        
        echo "[$count/$total_images] Downloading: $image"
        
        # Transform image reference into filesystem-safe directory name
        # Replace special characters (/, :) to prevent directory traversal issues
        # Best Practice: Sanitize user-controlled input (image names) before filesystem operations
        local image_name=$(echo "$image" | sed 's|docker.io/||' | sed 's|/|_|g' | sed 's|:|_|g')
        local dest_dir="${DOWNLOADS_DIR}/${image_name}"
        
        # Download image using skopeo in OCI directory format
        # --override-arch amd64: Force AMD64 even on ARM hosts for consistency
        # dir: format preserves OCI structure for registry import
        # Best Practice: Use 2>&1 to capture both stdout and stderr for proper error handling
        if skopeo copy --override-arch amd64 "docker://$image" "dir:$dest_dir" 2>&1; then
            success=$((success + 1))
            echo "  ✓ Successfully downloaded to: $dest_dir"
        else
            failed=$((failed + 1))
            echo "  ✗ Failed to download: $image"
        fi
        
        echo ""
    done < "$combined_images"
    
    # Display comprehensive summary with metrics
    # Best Practice: Always provide actionable feedback to users
    echo "=========================================="
    echo "Download Summary"
    echo "=========================================="
    echo "Total images: $total_images"
    echo "Successful: $success"
    echo "Failed: $failed"
    echo "Download directory: $DOWNLOADS_DIR"
    echo "=========================================="
    
    # Cleanup temporary files
    rm -rf "$TEMP_DIR"
    
    # Return appropriate exit code based on failures
    # Best Practice: Exit codes enable automation and error detection in CI/CD
    return $([[ $failed -eq 0 ]] && echo 0 || echo 1)
}

#=============================================================================
# Function: action_image_push
# Description: Pushes downloaded images to a private/alternative registry
#              with support for authenticated and unauthenticated registries
# Parameters: (all via flags)
#   --registry <URL>        - Target registry URL (required)
#   --no-auth               - Skip authentication (for insecure registries)
#   --password-file <path>  - Base64-encoded password file
#   --download-dir <path>   - Source directory for images
# Returns: 0 if all pushes succeed, 1 if any failures occur
# Security: Supports secure credential input via file or interactive prompt
#=============================================================================

action_image_push() {
    # Check and install dependencies if needed
    if ! install_dependencies; then
        echo "Error: Required dependencies not available"
        return 1
    fi
    
    # Initialize variables with defaults
    local DOWNLOADS_DIR="./downloads"
    local REGISTRY_URL=""
    local NO_AUTH=false
    local USERNAME=""
    local PASSWORD=""
    local PASSWORD_FILE=""
    
    # Parse command-line arguments using standard flag pattern
    # Best Practice: Use explicit flags instead of positional arguments for clarity
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --registry)
                REGISTRY_URL="$2"
                shift 2
                ;;
            --no-auth)
                NO_AUTH=true
                shift
                ;;
            --password-file)
                PASSWORD_FILE="$2"
                shift 2
                ;;
            --download-dir)
                DOWNLOADS_DIR="$2"
                shift 2
                ;;
            *)
                echo "Error: Unknown option for action_image_push: $1"
                return 1
                ;;
        esac
    done
    
    # Input validation: Ensure required parameters are provided
    # Best Practice: Fail fast with clear error messages
    if [[ -z "$REGISTRY_URL" ]]; then
        echo "Error: --registry flag is required"
        echo "Usage: action_image_push --registry <registry-url> [--no-auth] [--password-file <path>] [--download-dir <path>]"
        return 1
    fi
    
    # Validate source directory exists
    # Best Practice: Validate preconditions before starting expensive operations
    if [[ ! -d "$DOWNLOADS_DIR" ]]; then
        echo "Error: Downloads directory does not exist: $DOWNLOADS_DIR"
        echo "Please run --download first to download the images."
        return 1
    fi
    
    # Authentication handling with security best practices
    local SKOPEO_AUTH_ARGS=""
    
    if [[ "$NO_AUTH" == false ]]; then
        # Interactive username prompt if not in environment
        # Best Practice: Prompt for credentials interactively to avoid CLI history exposure
        if [[ -z "$USERNAME" ]]; then
            read -p "Registry username: " USERNAME
        fi
        
        # Secure password handling with multiple input methods
        if [[ -n "$PASSWORD_FILE" ]]; then
            # Validate password file exists before attempting to read
            if [[ ! -f "$PASSWORD_FILE" ]]; then
                echo "Error: Password file not found: $PASSWORD_FILE"
                return 1
            fi
            # Decode base64-encoded password from file
            # Best Practice: Base64 encoding prevents accidental password exposure in logs
            # Note: This is encoding, not encryption - use proper secrets management in production
            PASSWORD=$(base64 -d "$PASSWORD_FILE")
        else
            # Silent password prompt with no echo (-s flag)
            # Best Practice: Never echo passwords to terminal
            read -s -p "Registry password: " PASSWORD
            echo ""
        fi
        
        # Construct authentication arguments for skopeo
        # Note: Password will be passed via command line - ensure process table is protected
        SKOPEO_AUTH_ARGS="--dest-creds ${USERNAME}:${PASSWORD}"
    fi
    
    echo "=========================================="
    echo "Image Push Process Started"
    echo "Registry: $REGISTRY_URL"
    echo "Source directory: $DOWNLOADS_DIR"
    echo "Authentication: $([[ "$NO_AUTH" == true ]] && echo "Disabled" || echo "Enabled")"
    echo "=========================================="
    echo ""
    
    # Re-fetch image list to ensure consistency with downloaded images
    # Best Practice: Single source of truth for image manifest
    local GITHUB_API="https://api.github.com/repos/rancher/rke2/releases/latest"
    local CNI_GITHUB_API="https://api.github.com/repos/rancher/image-build-cni-plugins/releases/latest"
    local TEMP_DIR=$(mktemp -d)
    
    # Fetch RKE2 release version
    local release_info=$(curl -s "$GITHUB_API")
    local version=$(echo "$release_info" | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
    
    if [[ -z "$version" ]]; then
        echo "Error: Could not determine latest RKE2 version"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Download RKE2 image manifest
    local images_url="https://github.com/rancher/rke2/releases/download/${version}/rke2-images-all.linux-amd64.txt"
    local images_file="${TEMP_DIR}/rke2-images-all.linux-amd64.txt"
    
    if ! curl -sSL -o "$images_file" "$images_url"; then
        echo "Error: Failed to download RKE2 images list"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Fetch CNI plugins version
    local cni_release_info=$(curl -s "$CNI_GITHUB_API")
    local cni_version=$(echo "$cni_release_info" | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
    
    if [[ -z "$cni_version" ]]; then
        echo "Error: Could not determine latest CNI plugins version"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Create unified image list
    local combined_images="${TEMP_DIR}/all-images.txt"
    cat "$images_file" > "$combined_images"
    echo "docker.io/rancher/hardened-cni-plugins:$cni_version" >> "$combined_images"
    
    local total_images=$(wc -l < "$combined_images")
    echo "Total images to push: $total_images"
    echo ""
    
    # Initialize push metrics
    local count=0
    local success=0
    local failed=0
    
    # Iterate through image manifest and push each to target registry
    while IFS= read -r image; do
        count=$((count + 1))
        
        # Skip empty lines
        [[ -z "$image" ]] && continue
        
        # Map source directory using same transformation as download
        # Best Practice: Maintain naming consistency across operations
        local image_name=$(echo "$image" | sed 's|docker.io/||' | sed 's|/|_|g' | sed 's|:|_|g')
        local source_dir="${DOWNLOADS_DIR}/${image_name}"
        
        # Verify image was downloaded before attempting push
        # Best Practice: Graceful degradation - skip missing images rather than failing entire operation
        if [[ ! -d "$source_dir" ]]; then
            echo "[$count/$total_images] Skipping (not downloaded): $image"
            failed=$((failed + 1))
            continue
        fi
        
        # Construct target image reference by replacing registry prefix
        # Preserves namespace and tag structure for compatibility
        local image_without_registry=$(echo "$image" | sed 's|^docker\.io/||')
        local target_image="${REGISTRY_URL}/${image_without_registry}"
        
        echo "[$count/$total_images] Pushing: $image"
        echo "  Source: $source_dir"
        echo "  Target: $target_image"
        
        # Push image to target registry using skopeo
        # --override-arch amd64: Ensure architecture consistency
        # $SKOPEO_AUTH_ARGS: Contains credentials if authentication is enabled
        if skopeo copy --override-arch amd64 $SKOPEO_AUTH_ARGS "dir:$source_dir" "docker://$target_image" 2>&1; then
            success=$((success + 1))
            echo "  ✓ Successfully pushed"
        else
            failed=$((failed + 1))
            echo "  ✗ Failed to push"
        fi
        
        echo ""
    done < "$combined_images"
    
    # Display operation summary
    echo "=========================================="
    echo "Push Summary"
    echo "=========================================="
    echo "Total images: $total_images"
    echo "Successful: $success"
    echo "Failed: $failed"
    echo "Registry: $REGISTRY_URL"
    echo "=========================================="
    
    # Cleanup
    rm -rf "$TEMP_DIR"
    
    # Return success only if all operations succeeded
    return $([[ $failed -eq 0 ]] && echo 0 || echo 1)
}

#=============================================================================
# Function: usage
# Description: Displays comprehensive help information and usage examples
# Best Practice: Always provide --help for complex CLI tools
#=============================================================================
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --prep                      Run action_image_prep to fetch and display latest RKE2 and CNI plugin images
    --download [DIR]            Run action_image_download to download all images using skopeo
                                Optional: Specify download directory (default: ./downloads)
    --push                      Run action_image_push to push downloaded images to a registry
        --registry <URL>        Registry URL (required with --push)
        --no-auth               Registry does not require authentication
        --password-file <FILE>  Path to base64-encoded password file
        --download-dir <DIR>    Path to downloads directory (default: ./downloads)
    -h, --help                  Show this help message

Examples:
    $0 --prep
    $0 --download
    $0 --download /path/to/custom/downloads
    $0 --push --registry registry.example.com:5000 --no-auth
    $0 --push --registry registry.example.com:5000
    $0 --push --registry registry.example.com:5000 --password-file /path/to/password.b64

EOF
}

#=============================================================================
# Main Script Execution
# Description: Entry point when script is executed directly (not sourced)
# Best Practice: Allow both direct execution and sourcing for library use
#=============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Require at least one argument
    # Best Practice: Show help by default rather than executing arbitrary actions
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi
    
    # Parse and route to appropriate function based on first argument
    # Best Practice: Use case statements for clear, maintainable CLI routing
    case "$1" in
        --prep)
            action_image_prep
            ;;
        --download)
            # Support optional custom download directory
            if [[ -n "$2" ]]; then
                action_image_download "$2"
            else
                action_image_download
            fi
            ;;
        --push)
            # Forward all remaining arguments to push function
            # Best Practice: shift removes --push, passing remaining flags to function
            shift
            action_image_push "$@"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            # Unknown option error with helpful guidance
            echo "Error: Unknown option: $1"
            echo ""
            usage
            exit 1
            ;;
    esac
fi
