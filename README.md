# Packer OCI Image Builder for Airgap GitLab CI/CD

Build Packer container images for use in airgapped GitLab CI/CD pipelines running AMI builds in AWS.

## Overview

This project creates two images:
1. **Base Image**: `hashicorp/packer:1.14.2` (transferred as-is)
2. **CI/CD Image**: Enhanced image with AWS CLI, Git, and common utilities

## Dependencies Included

- AWS CLI (installed via pip for Alpine compatibility)
- Packer Ansible Plugin v1.1.4
- Ansible (core 2.18.6)
- git
- openssh-client
- curl, wget, unzip, tar, gzip
- jq (JSON processing)
- python3
- make
- bash

## Usage

### Internet-Connected Side

1. **Collect dependencies:**
   ```bash
   chmod +x collect-dependencies.sh
   ./collect-dependencies.sh
   ```

2. **Create transfer bundle:**
   ```bash
   tar -czf packer-airgap-bundle.tar.gz packer-base-1.14.2.tar dependencies/
   ```

3. **Transfer across airgap:**
   - Upload `packer-airgap-bundle.tar.gz` via your organization's approved method
   - Could be USB drive, secure file transfer, GUI upload, etc.

### Airgap Side

1. **Extract bundle:**
   ```bash
   tar -xzf packer-airgap-bundle.tar.gz
   ```

2. **Load and push base image to ECR:**
   ```bash
   # Load into Docker
   docker load < packer-base-1.14.2.tar

   # Tag for ECR
   docker tag hashicorp/packer:1.14.2 <ECR_REGISTRY>/packer-base:1.14.2

   # Login and push
   aws ecr get-login-password --region <REGION> | docker login --username AWS --password-stdin <ECR_REGISTRY>
   docker push <ECR_REGISTRY>/packer-base:1.14.2
   ```

3. **Configure environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your ECR registry and region
   ```

4. **Build and push CI/CD image:**
   ```bash
   chmod +x build-and-push.sh
   ./build-and-push.sh
   ```

## GitLab CI Configuration

Use the enhanced image in your `.gitlab-ci.yml`:

```yaml
packer-build:
  image: <ECR_REGISTRY>/packer-gitlab-cicd:latest
  script:
    - cd packer/
    - packer init .
    - packer validate .
    - packer build -var-file=vars.pkrvars.hcl .
  only:
    - main
```

## Using Ansible Provisioner

The image includes the Ansible provisioner plugin pre-installed. To use it in your Packer templates:

```hcl
packer {
  required_plugins {
    ansible = {
      version = "~> 1.1.4"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

source "amazon-ebs" "example" {
  # ... your AWS configuration
}

build {
  sources = ["source.amazon-ebs.example"]

  provisioner "ansible" {
    playbook_file = "./playbooks/configure.yml"
  }
}
```

**Note:** Since the plugin is pre-installed, `packer init` will skip downloading it in the airgap environment.

## Ansible Provisioner Considerations for Airgap Environments

When using Ansible provisioners in your Packer templates, be aware of these potential airgap challenges:

### 1. Ansible Galaxy Collections and Roles

**Problem:** Playbooks that use `ansible-galaxy install` or reference collections from Ansible Galaxy will fail in airgap.

**Impact:**
- Collections specified in `requirements.yml` won't download
- Community collections like `amazon.aws`, `community.general` won't be available
- Custom roles from Galaxy won't be accessible

**Solutions:**
- Pre-download collections on internet-connected machine and include in your Git repository
- Use `ansible-galaxy collection install -r requirements.yml -p ./collections` before transferring
- Bundle collections in the container image itself (requires extending Dockerfile)
- Keep all roles/tasks within your repository (no external dependencies)

### 2. Python Package Dependencies

**Problem:** Many Ansible modules require additional Python packages that aren't included by default.

**Common examples:**
- `boto3`, `botocore` - AWS modules (ec2, s3, etc.)
- `requests` - HTTP operations
- `jmespath` - JSON query operations
- `pywinrm` - Windows host management
- `netaddr` - Network address manipulation

**Impact:** Playbooks will fail with "missing Python library" errors during execution.

**Solutions:**
- Identify required packages from Ansible module documentation
- Install via pip in the Dockerfile: `RUN pip3 install boto3 botocore requests jmespath`
- Or bundle requirements.txt and install during image build
- Test playbooks thoroughly before airgap deployment

### 3. Ansible Version Management

**Problem:** Current setup uses whatever Ansible version Alpine provides (may not match your development version).

**Impact:**
- Module behavior differences between versions
- Deprecated features might break
- New features from newer versions unavailable

**Solutions:**
- Pin Ansible version in Dockerfile: `RUN pip3 install ansible==8.5.0`
- Document required Ansible version in your playbooks
- Test playbooks against the container's Ansible version before deployment

### 4. Ansible Configuration Files

**Problem:** `ansible.cfg` files might reference external resources or Galaxy servers.

**Check your ansible.cfg for:**
```ini
[galaxy]
server_list = galaxy  # Won't work in airgap

[defaults]
collections_paths = ~/.ansible/collections:/usr/share/ansible/collections
```

**Solutions:**
- Configure offline-friendly paths
- Disable Galaxy server references
- Point to local collection paths in your repository

### 5. Dynamic Inventory and External Lookups

**Problem:** Playbooks using dynamic inventory scripts or lookup plugins that fetch from external sources.

**Examples that won't work:**
- AWS EC2 dynamic inventory (queries AWS API)
- `lookup('url', 'https://...')` - External HTTP lookups
- `lookup('community.general.onepassword', ...)` - External secret managers

**Solutions:**
- Use static inventory files
- Pre-fetch data and use `lookup('file', ...)` instead
- Rely on Packer variables passed to Ansible rather than external lookups

### 6. Package Installation Within Playbooks

**Problem:** Playbooks that install packages on the AMI being built need package repositories.

**This still works:** Your AMI instance will have internet access during build (not the container).
- `apt install`, `yum install` work fine on the target instance
- Only the GitLab runner container is airgapped, not the EC2 instance being provisioned

**Important distinction:** The Packer container runs in airgap, but the EC2 instance it provisions can access the internet (or your VPC endpoints).

### Recommended Workflow

1. **Develop on internet-connected environment:**
   - Install collections: `ansible-galaxy collection install -r requirements.yml -p ./collections`
   - Test playbooks thoroughly
   - Document all Python dependencies

2. **Prepare for airgap:**
   - Commit collections to your Git repository
   - Update Dockerfile if additional Python packages needed
   - Remove/comment out Galaxy references in ansible.cfg

3. **Test in airgap-like environment:**
   - Build the container without network access
   - Run Ansible playbooks in --check mode
   - Verify all dependencies are bundled

## Notes

- All images are built for `linux/amd64` platform
- Base Packer version: `1.14.2`
- Base image: Alpine Linux (from hashicorp/packer:1.14.2)
- AWS CLI installed via pip (Alpine-compatible, no glibc needed)
- No automatic checksum verification (manual validation if needed)

## Technical Details

**AWS CLI Installation:**
The official AWS CLI v2 installer requires glibc, which is incompatible with Alpine Linux's musl libc. To avoid complex glibc shims that can cause segmentation faults, this project installs AWS CLI via pip, which works natively on Alpine.

**Packer Plugin Installation:**
The Ansible provisioner plugin is pre-installed in `/root/.packer.d/plugins/`. When you run `packer init`, it will detect the existing plugin and skip downloading, making it work in airgap environments.

## Troubleshooting

**Missing dependencies error during build:**
- Verify `dependencies/pip-packages/` contains AWS CLI wheel files
- Verify `dependencies/packer-plugins/packer-plugin-ansible.zip` exists
- Check that bundle was fully extracted
- If pip-packages is empty, AWS CLI will install from PyPI (requires internet during build)

**ECR authentication fails:**
- Ensure AWS CLI is configured with proper credentials
- Verify ECR registry URL is correct in `.env`

**Platform mismatch:**
- Always use `--platform linux/amd64` flag when building
