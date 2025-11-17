# Testing Guide: Packer OCI Builder for Airgapped Environments

This guide walks you through testing the Packer OCI container to ensure it has all necessary dependencies to run Packer in an airgapped environment.

## Table of Contents
1. [Understanding the Architecture](#understanding-the-architecture)
2. [Prerequisites](#prerequisites)
3. [Step 1: Collect Dependencies](#step-1-collect-dependencies)
4. [Step 2: Build the Container Locally](#step-2-build-the-container-locally)
5. [Step 3: Test Container Functionality](#step-3-test-container-functionality)
6. [Step 4: Simulate Airgapped Environment](#step-4-simulate-airgapped-environment)
7. [Step 5: Test with Real Packer Template](#step-5-test-with-real-packer-template)
8. [Troubleshooting](#troubleshooting)

---

## Understanding the Architecture

This project creates a Docker container with:
- **Base**: HashiCorp Packer 1.14.2 (Alpine Linux)
- **Dependencies**: AWS CLI, Git, Ansible, common utilities
- **Packer Plugins**: Ansible provisioner plugin (pre-installed)
- **Airgap Ready**: All dependencies bundled offline

The key to airgap compatibility is pre-downloading all dependencies so the container doesn't need internet access during build or runtime.

---

## Prerequisites

### On Your Internet-Connected Machine:
- Docker installed and running
- `pip3` installed (Python 3 package manager)
- `curl` available
- Internet connectivity
- At least 2GB free disk space

### Check Prerequisites:
```bash
# Verify Docker is running
docker --version
docker ps

# Verify pip3 is available
pip3 --version

# Verify curl is available
curl --version
```

---

## Step 1: Collect Dependencies

This step downloads all necessary dependencies for offline use.

### 1.1 Run the Dependency Collection Script

```bash
# Make the script executable
chmod +x collect-dependencies.sh

# Run the collection script
./collect-dependencies.sh
```

### 1.2 Verify Downloaded Dependencies

After the script completes, verify all dependencies were collected:

```bash
# Check directory structure
ls -lR dependencies/

# Verify critical files exist
echo "Checking Packer base image..."
ls -lh packer-base-1.14.2.tar

echo "Checking Packer Ansible plugin..."
ls -lh dependencies/packer-plugins/packer-plugin-ansible.zip

echo "Checking AWS CLI wheels..."
ls -lh dependencies/pip-packages/

echo "Checking APK packages (if created)..."
ls -lh dependencies/apk-packages/
```

### Expected Output:
```
dependencies/
├── apk-packages/           # Alpine packages (may be empty - will install online)
├── packages/               # Package list
│   └── package-list.txt
├── packer-plugins/
│   └── packer-plugin-ansible.zip
└── pip-packages/           # AWS CLI and dependencies
    ├── awscli-*.whl
    ├── botocore-*.whl
    ├── s3transfer-*.whl
    └── ... (many wheel files)

packer-base-1.14.2.tar      # Docker image (several hundred MB)
```

**Important Note**: The APK packages directory may be empty because collecting Alpine packages requires running on Alpine Linux. The Dockerfile will install these from the internet during the build. For true airgap, you'd need to collect APK packages on an Alpine system.

---

## Step 2: Build the Container Locally

### 2.1 Load the Base Packer Image

First, load the HashiCorp Packer base image into your local Docker:

```bash
# Load the Packer base image
docker load < packer-base-1.14.2.tar

# Verify it loaded correctly
docker images | grep packer
```

You should see:
```
hashicorp/packer   1.14.2   <image-id>   <created>   <size>
```

### 2.2 Build the Enhanced Image

Build the container with all dependencies:

```bash
# Build the image
docker build --platform linux/amd64 -t packer-gitlab-cicd:test .

# Check build was successful
docker images | grep packer-gitlab-cicd
```

### 2.3 Inspect the Build Logs

The build should show successful installation of:
- System packages (git, openssh, jq, etc.)
- AWS CLI via pip
- Packer Ansible plugin
- Verification of all tools

Look for these verification lines at the end:
```
Packer v1.14.2
aws-cli/X.X.X Python/3.X.X ...
git version X.X.X
jq-X.X
ansible [core X.X.X]
```

---

## Step 3: Test Container Functionality

### 3.1 Basic Container Tests

Test that the container runs and all tools are available:

```bash
# Test 1: Container starts and shows Packer version
docker run --rm packer-gitlab-cicd:test packer --version

# Test 2: AWS CLI is available
docker run --rm packer-gitlab-cicd:test aws --version

# Test 3: Git is available
docker run --rm packer-gitlab-cicd:test git --version

# Test 4: Ansible is available
docker run --rm packer-gitlab-cicd:test ansible --version

# Test 5: JQ is available
docker run --rm packer-gitlab-cicd:test jq --version

# Test 6: Python3 is available
docker run --rm packer-gitlab-cicd:test python3 --version

# Test 7: All tools together
docker run --rm packer-gitlab-cicd:test sh -c "packer --version && aws --version && git --version && ansible --version"
```

### 3.2 Verify Packer Plugin Installation

The Ansible plugin should be pre-installed:

```bash
# Check plugin directory
docker run --rm packer-gitlab-cicd:test ls -lR /root/.packer.d/plugins/

# Expected output should show:
# /root/.packer.d/plugins/github.com/hashicorp/ansible/
# └── packer-plugin-ansible_v1.1.4_x5.0_linux_amd64
```

### 3.3 Interactive Shell Test

Enter the container interactively to explore:

```bash
# Start interactive shell
docker run --rm -it packer-gitlab-cicd:test sh

# Inside container, test commands:
packer --version
aws --version
git --version
ansible --version
which packer
which aws
which git
which ansible
echo $PATH

# Check plugin location
ls -l /root/.packer.d/plugins/github.com/hashicorp/ansible/

# Exit container
exit
```

---

## Step 4: Simulate Airgapped Environment

This is the critical test - can the container work WITHOUT internet access?

### 4.1 Create a Test Network Without Internet

```bash
# Create an isolated Docker network (no internet access)
docker network create --internal airgap-test-network

# Verify network was created
docker network ls | grep airgap
```

### 4.2 Test Container in Isolated Network

```bash
# Run container on isolated network
docker run --rm --network airgap-test-network packer-gitlab-cicd:test packer --version

# This should still work because Packer is already in the container

# Test that internet is truly blocked
docker run --rm --network airgap-test-network packer-gitlab-cicd:test sh -c "ping -c 2 8.8.8.8 || echo 'Network isolated successfully'"
```

### 4.3 Create a Simple Packer Template for Testing

Create a minimal Packer template that uses the Ansible plugin:

```bash
# Create test directory
mkdir -p test-packer-template
cd test-packer-template

# Create a simple Packer template
cat > test-template.pkr.hcl << 'EOF'
packer {
  required_plugins {
    ansible = {
      version = "~> 1.1.4"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

# This is a minimal template that just validates
# In real use, you'd have AWS sources and provisioners
source "null" "test" {
  communicator = "none"
}

build {
  sources = ["source.null.test"]
}
EOF

# Create a simple Ansible playbook for testing
cat > test-playbook.yml << 'EOF'
---
- name: Test playbook
  hosts: all
  tasks:
    - name: Debug message
      debug:
        msg: "Ansible is working!"
EOF
```

### 4.4 Test Packer Init in Airgapped Network

```bash
# Test packer init (should detect pre-installed plugin)
docker run --rm \
  --network airgap-test-network \
  -v "$(pwd)":/workspace \
  packer-gitlab-cicd:test \
  sh -c "cd /workspace && packer init test-template.pkr.hcl"

# Expected output should indicate plugin is already installed
# Look for: "Installed plugin github.com/hashicorp/ansible v1.1.4"
# OR: "Plugin already installed"
```

### 4.5 Test Packer Validate

```bash
# Test packer validate
docker run --rm \
  --network airgap-test-network \
  -v "$(pwd)":/workspace \
  packer-gitlab-cicd:test \
  sh -c "cd /workspace && packer validate test-template.pkr.hcl"

# Should output: "The configuration is valid."
```

### 4.6 Cleanup Test Network

```bash
# Return to repo directory
cd ..

# Remove test network
docker network rm airgap-test-network
```

---

## Step 5: Test with Real Packer Template

For a more complete test, create a template that would actually build an AMI (but in validation mode).

### 5.1 Create AWS AMI Template

```bash
# Create test directory
mkdir -p test-aws-packer
cd test-aws-packer

cat > aws-test.pkr.hcl << 'EOF'
packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = "~> 1.1.4"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

source "amazon-ebs" "example" {
  region        = var.aws_region
  source_ami    = "ami-0c55b159cbfafe1f0"  # Example AMI
  instance_type = "t2.micro"
  ssh_username  = "ubuntu"
  ami_name      = "packer-test-{{timestamp}}"
}

build {
  sources = ["source.amazon-ebs.example"]

  provisioner "ansible" {
    playbook_file = "./playbook.yml"
  }
}
EOF

cat > playbook.yml << 'EOF'
---
- name: Configure AMI
  hosts: all
  become: yes
  tasks:
    - name: Update apt cache
      apt:
        update_cache: yes

    - name: Install nginx
      apt:
        name: nginx
        state: present
EOF
```

### 5.2 Test Template Validation

```bash
# Test packer init with AWS plugin
# NOTE: This will try to download the AWS plugin which won't work in airgap
# This demonstrates that you'd need to pre-install the AWS plugin too
docker run --rm \
  -v "$(pwd)":/workspace \
  packer-gitlab-cicd:test \
  sh -c "cd /workspace && packer init aws-test.pkr.hcl"

# Test validation
docker run --rm \
  -v "$(pwd)":/workspace \
  packer-gitlab-cicd:test \
  sh -c "cd /workspace && packer validate aws-test.pkr.hcl"
```

**Note**: If you need the AWS plugin in an airgapped environment, you'd need to:
1. Download it in `collect-dependencies.sh`
2. Copy it to the container in the Dockerfile
3. Place it in `/root/.packer.d/plugins/`

---

## Step 6: Create Bundle for Airgap Transfer

If all tests pass, create the transfer bundle:

```bash
# Return to repo root
cd /path/to/packer-oci-builder

# Create the bundle
tar -czf packer-airgap-bundle.tar.gz \
  packer-base-1.14.2.tar \
  dependencies/ \
  Dockerfile \
  build-and-push.sh \
  .env.example

# Check bundle size
ls -lh packer-airgap-bundle.tar.gz

# Verify bundle contents
tar -tzf packer-airgap-bundle.tar.gz | head -20
```

---

## Verification Checklist

Before considering the container ready for airgapped deployment:

- [ ] Base Packer image loads successfully
- [ ] Enhanced image builds without errors
- [ ] Packer CLI works (`packer --version`)
- [ ] AWS CLI works (`aws --version`)
- [ ] Git works (`git --version`)
- [ ] Ansible works (`ansible --version`)
- [ ] JQ works (`jq --version`)
- [ ] Ansible plugin is pre-installed in `/root/.packer.d/plugins/`
- [ ] `packer init` detects pre-installed Ansible plugin
- [ ] `packer validate` works on test template
- [ ] Container works in isolated network (no internet)
- [ ] All dependencies are bundled (no downloads during build/runtime)

---

## Troubleshooting

### Issue: pip-packages directory is empty

**Cause**: `pip3` not installed on collection machine

**Solution**: Install Python 3 and pip:
```bash
# Ubuntu/Debian
sudo apt-get install python3-pip

# macOS
brew install python3

# Then re-run collection script
./collect-dependencies.sh
```

**Workaround**: If you can't install pip3, the Dockerfile will attempt to install AWS CLI from PyPI (requires internet during build).

---

### Issue: Docker build fails with "awscli not found"

**Cause**: pip-packages directory is empty

**Fix**: The Dockerfile has a fallback:
```dockerfile
RUN pip3 install --no-cache-dir --break-system-packages --no-index --find-links=/tmp/pip-packages awscli || \
    pip3 install --no-cache-dir --break-system-packages awscli
```

The `||` means it will try online installation if offline fails. For true airgap, ensure pip-packages is populated.

---

### Issue: Packer init tries to download plugins

**Cause**: Plugin not correctly installed or version mismatch

**Debug**:
```bash
# Check plugin location
docker run --rm packer-gitlab-cicd:test ls -lR /root/.packer.d/plugins/

# Check Packer recognizes it
docker run --rm packer-gitlab-cicd:test packer plugins installed
```

**Fix**: Ensure plugin file is executable:
```dockerfile
chmod +x packer-plugin-ansible_v1.1.4_x5.0_linux_amd64
```

---

### Issue: Container can access internet in "isolated" network

**Cause**: Docker network not properly isolated

**Fix**: Ensure you used `--internal` flag:
```bash
docker network create --internal airgap-test-network
```

Verify:
```bash
docker run --rm --network airgap-test-network alpine ping -c 2 8.8.8.8
# Should fail with "Network is unreachable" or timeout
```

---

### Issue: Build-and-push.sh looks for wrong dependency path

**Current Issue**: build-and-push.sh checks for `dependencies/binaries/awscliv2.zip` but the project uses pip-packages.

**Fix**: The check in build-and-push.sh is outdated. You can either:

1. Comment out the check (lines 28-32 in build-and-push.sh)
2. Or modify it to check for pip-packages:
```bash
if [ ! -d "dependencies/pip-packages" ] || [ -z "$(ls -A dependencies/pip-packages)" ]; then
    echo "WARNING: dependencies/pip-packages is empty"
    echo "AWS CLI will be installed from PyPI during build (requires internet)"
fi
```

---

### Issue: Platform mismatch warnings

**Symptom**: Warnings about platform compatibility

**Fix**: Always specify platform:
```bash
docker build --platform linux/amd64 -t packer-gitlab-cicd:test .
docker run --platform linux/amd64 --rm packer-gitlab-cicd:test packer --version
```

---

## Advanced Testing: Full Airgap Simulation

For the most rigorous test, simulate the complete airgap workflow:

### 1. Internet Side
```bash
# Collect dependencies
./collect-dependencies.sh

# Create bundle
tar -czf packer-airgap-bundle.tar.gz packer-base-1.14.2.tar dependencies/

# Simulate transfer (copy to different directory)
cp packer-airgap-bundle.tar.gz /tmp/airgap-simulation/
```

### 2. Airgap Side (simulate by blocking internet)
```bash
cd /tmp/airgap-simulation/

# Extract bundle
tar -xzf packer-airgap-bundle.tar.gz

# Load base image
docker load < packer-base-1.14.2.tar

# Build with NO internet access
# Create iptables rule to block outbound connections from Docker
# (Requires root/sudo - be careful!)
sudo iptables -I DOCKER-USER -j REJECT

# Build image (should work offline)
docker build --platform linux/amd64 -t packer-gitlab-cicd:airgap-test .

# Restore internet access
sudo iptables -D DOCKER-USER -j REJECT

# Test the built image
docker run --rm packer-gitlab-cicd:airgap-test packer --version
```

**Warning**: Be careful with iptables rules. Make sure you can restore connectivity!

---

## Success Criteria

Your container is ready for airgapped deployment when:

1. **All dependencies are bundled**: No internet downloads during build
2. **Packer runs**: `packer --version` succeeds
3. **AWS CLI runs**: `aws --version` succeeds
4. **Ansible runs**: `ansible --version` succeeds
5. **Plugins pre-installed**: `packer init` doesn't download anything
6. **Validates templates**: `packer validate` works
7. **Isolated network test passes**: Container works without internet
8. **Bundle is portable**: Can transfer and rebuild on another machine

---

## Next Steps

After successful testing:

1. **Document any additional dependencies** your specific Packer templates need
2. **Extend Dockerfile** to include additional Packer plugins if needed
3. **Test with your actual Packer templates** (not just the examples)
4. **Update collect-dependencies.sh** to include any additional plugins
5. **Transfer bundle** to airgapped environment
6. **Push to ECR** using build-and-push.sh
7. **Configure GitLab CI** to use the image

---

## Additional Resources

- [Packer Documentation](https://developer.hashicorp.com/packer/docs)
- [Packer Plugin Installation](https://developer.hashicorp.com/packer/docs/plugins/install)
- [AWS CLI Installation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Docker Multi-stage Builds](https://docs.docker.com/build/building/multi-stage/)
- [Alpine Package Management](https://wiki.alpinelinux.org/wiki/Alpine_Package_Keeper)
