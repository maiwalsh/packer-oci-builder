FROM hashicorp/packer:1.14.2

# Install system dependencies from local APK bundles (airgap compatible)
COPY dependencies/apk-packages/ /tmp/apk-packages/
RUN apk add --upgrade --no-cache --allow-untrusted /tmp/apk-packages/*.apk && \
    rm -rf /tmp/apk-packages

# Install AWS CLI via pip from bundled packages (for airgap compatibility)
COPY dependencies/pip-packages/ /tmp/pip-packages/
RUN pip3 install --no-cache-dir --break-system-packages --no-index --find-links=/tmp/pip-packages awscli || \
    pip3 install --no-cache-dir --break-system-packages awscli

# Install Packer Ansible plugin
ARG ANSIBLE_PLUGIN_VERSION=1.1.4
COPY dependencies/packer-plugins/packer-plugin-ansible.zip /tmp/packer-plugin-ansible.zip
RUN mkdir -p /root/.packer.d/plugins/github.com/hashicorp/ansible && \
    cd /root/.packer.d/plugins/github.com/hashicorp/ansible && \
    unzip /tmp/packer-plugin-ansible.zip && \
    chmod +x packer-plugin-ansible_v${ANSIBLE_PLUGIN_VERSION}_x5.0_linux_amd64 && \
    rm /tmp/packer-plugin-ansible.zip

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
