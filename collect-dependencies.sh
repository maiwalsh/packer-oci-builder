#!/bin/bash
set -e

# Script to collect all dependencies for airgap transfer
# Run this on an internet-connected machine

DEPS_DIR="./dependencies"
ARCH="linux-amd64"

echo "=== Packer Dependencies Collection Script ==="
echo "Creating dependencies directory..."
mkdir -p "$DEPS_DIR"/{binaries,packages,packer-plugins,pip-packages,apk-packages}

# AWS CLI (via pip for Alpine compatibility)
echo "Downloading AWS CLI pip packages..."
if command -v pip3 &> /dev/null; then
    pip3 download awscli -d "$DEPS_DIR/pip-packages"
    echo "AWS CLI packages downloaded to $DEPS_DIR/pip-packages"
else
    echo "WARNING: pip3 not found. AWS CLI will be installed from PyPI during Docker build."
    echo "This will require internet access during the build process."
    echo "To fix: Install python3-pip and re-run this script."
    touch "$DEPS_DIR/pip-packages/.gitkeep"
fi

# Packer Ansible Plugin
echo "Downloading Packer Ansible plugin..."
ANSIBLE_PLUGIN_VERSION="1.1.4"
curl -sL "https://releases.hashicorp.com/packer-plugin-ansible/${ANSIBLE_PLUGIN_VERSION}/packer-plugin-ansible_${ANSIBLE_PLUGIN_VERSION}_linux_amd64.zip" -o "$DEPS_DIR/packer-plugins/packer-plugin-ansible.zip"

# Download packages for offline installation
echo "Downloading system packages..."
PACKAGES=(
    "git"
    "openssh-client"
    "ca-certificates"
    "curl"
    "wget"
    "unzip"
    "tar"
    "gzip"
    "jq"
    "python3"
    "python3-pip"
    "make"
)

# Create a simple package list file
cat > "$DEPS_DIR/packages/package-list.txt" <<EOF
# System packages to install in Dockerfile
# These will be installed via apt-get in the container
git
openssh-client
ca-certificates
curl
wget
unzip
tar
gzip
jq
python3
python3-pip
make
EOF

echo "Downloading Packer base image..."
docker pull --platform linux/amd64 hashicorp/packer:1.14.2
docker save hashicorp/packer:1.14.2 -o packer-base-1.14.2.tar
echo "Saved packer-base-1.14.2.tar"

echo ""
echo "=== Collection Complete ==="
echo "Files collected:"
echo "  - packer-base-1.14.2.tar (base image)"
echo "  - $DEPS_DIR/pip-packages/ (AWS CLI pip wheels)"
echo "  - $DEPS_DIR/packer-plugins/ (Ansible provisioner plugin)"
echo "  - $DEPS_DIR/packages/ (package list)"
echo "  - $DEPS_DIR/apk-packages/ (empty - APK packages installed during build)"
echo ""
echo "Note: System packages (git, jq, etc.) are installed from Alpine repos during"
echo "Docker build. They cannot be bundled without running on Alpine Linux, but"
echo "they will be cached in the final Docker image for airgap use."
echo ""
echo "To transfer:"
echo "  1. Create archive: tar -czf packer-airgap-bundle.tar.gz packer-base-1.14.2.tar dependencies/"
echo "  2. Transfer packer-airgap-bundle.tar.gz across airgap"
echo "  3. Extract on other side: tar -xzf packer-airgap-bundle.tar.gz"
