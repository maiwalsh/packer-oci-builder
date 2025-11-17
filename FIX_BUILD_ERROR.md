# Fix: Docker Build Failure - Missing dependencies/apk-packages Directory

## Issue
When running `docker build --platform linux/amd64 -t packer-gitlab-cicd:test .`, the build fails with:
```
ERROR: failed to solve: failed to compute cache key: failed to calculate checksum of ref:
"/dependencies/apk-packages": not found
```

## Root Cause
The Dockerfile expected the `dependencies/apk-packages/` directory to exist with bundled Alpine packages. However:
1. The `collect-dependencies.sh` script doesn't create this directory
2. Collecting Alpine APK packages requires running on Alpine Linux
3. The directory structure wasn't created before attempting to COPY it

## What Changed
I've fixed both the Dockerfile and collect-dependencies.sh:

### Dockerfile Changes
1. **System packages now installed directly via apk**: Instead of trying to copy bundled APK packages, the Dockerfile now installs them directly from Alpine repositories during build. These packages will be cached in the final image.

2. **Made pip-packages optional**: If no bundled pip packages exist, falls back to installing AWS CLI from PyPI (requires internet during build).

3. **Made packer-plugins optional**: If the Ansible plugin isn't bundled, it will need to be downloaded during `packer init` (requires internet).

### collect-dependencies.sh Changes
1. **Creates all required directories**: Now creates `apk-packages/` directory even though it remains empty
2. **Better warning messages**: Clearer explanation when pip3 isn't available
3. **Updated summary**: Explains why apk-packages is empty

## How to Proceed

### Option 1: Pull the Latest Changes (Recommended)
```bash
# Pull the latest changes with the fix
git pull origin claude/test-doc-creation-0179cJPKKrQbS2JZCUEFrpxH

# Now run the dependency collection
./collect-dependencies.sh

# Build the container (should work now)
docker build --platform linux/amd64 -t packer-gitlab-cicd:test .
```

### Option 2: Manual Quick Fix (If you can't pull changes)
If you're testing locally and just need to get unblocked immediately:

```bash
# Create the missing directories manually
mkdir -p dependencies/apk-packages
mkdir -p dependencies/pip-packages
mkdir -p dependencies/packer-plugins

# Run the dependency collection script
./collect-dependencies.sh

# Build the container
docker build --platform linux/amd64 -t packer-gitlab-cicd:test .
```

## What's Different Now

### Before (Broken)
- Dockerfile tried to COPY a directory that didn't exist
- Build failed before even starting

### After (Fixed)
- Dockerfile installs system packages directly from Alpine repos
- Build works even without bundled dependencies
- If you run `collect-dependencies.sh`, it bundles what it can:
  - ✅ Packer base image
  - ✅ AWS CLI pip packages (if pip3 installed)
  - ✅ Packer Ansible plugin
  - ℹ️ System packages (installed during build)

## Impact on Airgap Capability

### What Requires Internet During Build
- **System packages** (git, jq, etc.): Installed from Alpine repos during `docker build`
- **AWS CLI** (if pip3 wasn't available during collection): Installed from PyPI during `docker build`
- **Packer plugins** (if not bundled): Downloaded during `packer init`

### What Doesn't Require Internet
Once the image is built, it contains:
- ✅ Packer 1.14.2
- ✅ All system packages (git, jq, ansible, etc.)
- ✅ AWS CLI
- ✅ Packer Ansible plugin (if bundled)

The built image can run in a completely airgapped environment. The only internet requirement is during the initial build on the internet-connected side.

## Updated Workflow

### Internet-Connected Side
```bash
# 1. Collect dependencies (requires internet)
./collect-dependencies.sh

# 2. Build image (requires internet for Alpine packages)
docker build --platform linux/amd64 -t packer-gitlab-cicd:local .

# 3. Save the built image
docker save packer-gitlab-cicd:local -o packer-cicd-image.tar

# 4. Create transfer bundle
tar -czf packer-airgap-bundle.tar.gz \
  packer-base-1.14.2.tar \
  packer-cicd-image.tar \
  dependencies/
```

### Airgap Side
```bash
# 1. Extract bundle
tar -xzf packer-airgap-bundle.tar.gz

# 2. Load BOTH images
docker load < packer-base-1.14.2.tar
docker load < packer-cicd-image.tar

# 3. Tag for ECR
docker tag packer-gitlab-cicd:local <ECR_REGISTRY>/packer-gitlab-cicd:latest

# 4. Push to ECR
aws ecr get-login-password --region <REGION> | \
  docker login --username AWS --password-stdin <ECR_REGISTRY>
docker push <ECR_REGISTRY>/packer-gitlab-cicd:latest
```

**Key Point**: You can now transfer the already-built image (`packer-cicd-image.tar`) instead of building it in the airgap environment!

## Alternative: Build in Airgap (If Needed)

If you prefer to build in the airgap environment (not recommended unless you have local Alpine repos):

```bash
# Extract bundle
tar -xzf packer-airgap-bundle.tar.gz

# Load base image
docker load < packer-base-1.14.2.tar

# Build (requires local Alpine package mirror)
docker build --platform linux/amd64 -t packer-gitlab-cicd:local .
```

This requires:
- Local Alpine package mirror for apk packages
- Or Docker configured to use a local registry mirror

## Testing the Fix

After building the image, run the automated tests:

```bash
# Basic tests
./test-container.sh packer-gitlab-cicd:test

# With airgap simulation
./test-container.sh packer-gitlab-cicd:test true
```

All tests should pass, confirming:
- ✅ Packer is installed
- ✅ AWS CLI is installed
- ✅ Git, Ansible, JQ, etc. are installed
- ✅ Packer Ansible plugin is pre-installed
- ✅ Container works without internet

## Summary

The build now works by:
1. Installing system packages directly (they're cached in the image)
2. Using bundled pip packages if available (falls back to PyPI)
3. Using bundled Packer plugins if available (warns if missing)

The key insight: For true airgap deployment, build the image on the internet-connected side, then transfer the **built image** rather than trying to build from scratch in the airgap environment.
