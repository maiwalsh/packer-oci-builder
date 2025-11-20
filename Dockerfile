FROM hashicorp/packer:1.14.2

# Install system dependencies directly via apk
# Note: These need to be installed from Alpine repos as collecting APK packages
# requires running on Alpine Linux. They will be cached in the final image.
RUN apk add --no-cache \
    git \
    openssh-client \
    ca-certificates \
    curl \
    wget \
    unzip \
    tar \
    gzip \
    jq \
    python3 \
    py3-pip \
    make \
    bash \
    ansible

# Install AWS CLI via pip from bundled packages (for airgap compatibility)
COPY dependencies/pip-packages /tmp/pip-packages
RUN if [ -n "$(ls /tmp/pip-packages/*.whl 2>/dev/null)" ]; then \
        echo "Installing AWS CLI from bundled packages..."; \
        pip3 install --no-cache-dir --break-system-packages --no-index --find-links=/tmp/pip-packages awscli; \
    else \
        echo "No bundled packages found. Installing AWS CLI from PyPI..."; \
        pip3 install --no-cache-dir --break-system-packages awscli; \
    fi && \
    rm -rf /tmp/pip-packages

# Install Packer Ansible plugin
ARG ANSIBLE_PLUGIN_VERSION=1.1.4
COPY dependencies/packer-plugins /tmp/packer-plugins
RUN if [ -f /tmp/packer-plugins/packer-plugin-ansible.zip ]; then \
        echo "Installing Ansible plugin from bundled package..."; \
        mkdir -p /root/.packer.d/plugins/github.com/hashicorp/ansible && \
        cd /root/.packer.d/plugins/github.com/hashicorp/ansible && \
        unzip /tmp/packer-plugins/packer-plugin-ansible.zip && \
        chmod +x packer-plugin-ansible_v${ANSIBLE_PLUGIN_VERSION}_x5.0_linux_amd64 && \
        echo "Ansible plugin installed successfully"; \
    else \
        echo "WARNING: Ansible plugin not found in bundle. Will need to download during 'packer init'"; \
    fi && \
    rm -rf /tmp/packer-plugins

# Verify installations
RUN packer --version && \
    aws --version && \
    git --version && \
    jq --version && \
    ansible --version

# Set working directory
WORKDIR /workspace

# Default command
CMD ["packer"]
