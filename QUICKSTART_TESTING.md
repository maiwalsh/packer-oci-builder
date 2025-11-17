# Quick Start: Testing Your Packer Container

This is a quick reference guide to test your Packer container build. For detailed information, see [TESTING_GUIDE.md](./TESTING_GUIDE.md).

## TL;DR - Fastest Path to Test

```bash
# 1. Collect dependencies (requires internet, pip3, docker)
./collect-dependencies.sh

# 2. Load base image
docker load < packer-base-1.14.2.tar

# 3. Build container
docker build --platform linux/amd64 -t packer-gitlab-cicd:test .

# 4. Run automated tests
./test-container.sh packer-gitlab-cicd:test

# 5. Run automated tests WITH airgap simulation
./test-container.sh packer-gitlab-cicd:test true
```

## What Gets Tested

The automated test script (`test-container.sh`) validates:

### Phase 1: Basic Tools (10 tests)
- ✓ Docker image exists
- ✓ Packer installed and working
- ✓ AWS CLI installed and working
- ✓ Git installed
- ✓ Ansible installed
- ✓ JQ installed
- ✓ Python3 installed
- ✓ SSH client available
- ✓ Curl available
- ✓ Unzip available

### Phase 2: Packer Plugins (3 tests)
- ✓ Ansible plugin directory exists
- ✓ Ansible plugin binary present
- ✓ Plugin is executable

### Phase 3: Packer Functionality (2 tests)
- ✓ `packer init` detects pre-installed plugin
- ✓ `packer validate` works on test template

### Phase 4: AWS CLI (2 tests)
- ✓ AWS help commands work
- ✓ AWS S3 subcommands available

### Phase 5: Ansible (2 tests)
- ✓ Ansible playbook syntax checking
- ✓ Ansible inventory commands work

### Phase 6: Airgap Simulation (3 tests) - Optional
- ✓ Internet is blocked in isolated network
- ✓ Packer works without internet
- ✓ Packer validate works without internet

## Expected Output

Successful test run should look like:

```
=== Packer Container Testing Script ===
Testing image: packer-gitlab-cicd:test

=== Phase 1: Basic Container Tests ===

Test 1: Docker image exists ... PASSED
Test 2: Packer is installed ... PASSED
Test 3: AWS CLI is installed ... PASSED
Test 4: Git is installed ... PASSED
Test 5: Ansible is installed ... PASSED
...

=== Test Summary ===
Total Tests: 19
Passed: 19
Failed: 0

Success Rate: 100%

✓ All tests passed! Container is ready for airgapped deployment.
```

## Manual Quick Tests

If you prefer to test manually:

```bash
# Test Packer
docker run --rm packer-gitlab-cicd:test packer --version

# Test AWS CLI
docker run --rm packer-gitlab-cicd:test aws --version

# Test Ansible
docker run --rm packer-gitlab-cicd:test ansible --version

# Check plugin is installed
docker run --rm packer-gitlab-cicd:test ls -l /root/.packer.d/plugins/github.com/hashicorp/ansible/

# Interactive exploration
docker run --rm -it packer-gitlab-cicd:test sh
```

## Testing Airgap Capability

The most important test is ensuring the container works WITHOUT internet:

```bash
# Create isolated network (no internet)
docker network create --internal airgap-test

# Test Packer works without internet
docker run --rm --network airgap-test packer-gitlab-cicd:test packer --version

# Should output: Packer v1.14.2

# Verify internet is truly blocked
docker run --rm --network airgap-test packer-gitlab-cicd:test ping -c 2 8.8.8.8
# Should fail or timeout

# Cleanup
docker network rm airgap-test
```

## Common Issues

### Issue: "dependencies/apk-packages: not found" during Docker build
**Cause**: Running an older version of the Dockerfile that expected pre-bundled APK packages

**Fix**:
```bash
# Pull the latest changes
git pull origin claude/test-doc-creation-0179cJPKKrQbS2JZCUEFrpxH

# Or manually create directories
mkdir -p dependencies/{apk-packages,pip-packages,packer-plugins}

# Then run collection and build
./collect-dependencies.sh
docker build --platform linux/amd64 -t packer-gitlab-cicd:test .
```

See [FIX_BUILD_ERROR.md](./FIX_BUILD_ERROR.md) for detailed explanation.

### Issue: "pip-packages is empty"
**Cause**: pip3 not installed when running collect-dependencies.sh

**Fix**:
```bash
# Install pip3
sudo apt-get install python3-pip  # Ubuntu/Debian
# or
brew install python3  # macOS

# Re-run collection
./collect-dependencies.sh
```

**Note**: If you can't install pip3, the build will still work - it will download AWS CLI from PyPI during the Docker build (requires internet).

### Issue: "No space left on device"
**Cause**: Docker images are large (several hundred MB)

**Fix**:
```bash
# Clean up old images
docker system prune -a

# Check available space
df -h
```

### Issue: Tests fail with "network unreachable"
**Cause**: Could be a good thing! Means airgap is working.

**Check**: Make sure you're running the right test:
- Normal tests: `./test-container.sh packer-gitlab-cicd:test`
- Airgap tests: `./test-container.sh packer-gitlab-cicd:test true`

## Interpreting Test Results

### 100% Pass Rate (Green ✓)
- Container is ready for airgapped deployment
- All dependencies are bundled correctly
- Proceed with creating transfer bundle

### 80-99% Pass Rate (Yellow ⚠)
- Most functionality works
- Review failed tests
- Might be acceptable depending on your requirements
- Common: Some optional tools missing

### <80% Pass Rate (Red ✗)
- Container has significant issues
- Do NOT deploy to airgap environment
- Review build logs
- Check dependency collection completed successfully

## Next Steps After Successful Testing

1. **Create Transfer Bundle**:
   ```bash
   tar -czf packer-airgap-bundle.tar.gz \
     packer-base-1.14.2.tar \
     dependencies/ \
     Dockerfile \
     build-and-push.sh \
     .env.example
   ```

2. **Transfer to Airgap Environment**:
   - Use approved file transfer method
   - USB drive, secure upload, etc.

3. **Deploy in Airgap**:
   ```bash
   # Extract bundle
   tar -xzf packer-airgap-bundle.tar.gz

   # Load base image
   docker load < packer-base-1.14.2.tar

   # Configure environment
   cp .env.example .env
   # Edit .env with your ECR details

   # Build and push
   ./build-and-push.sh
   ```

4. **Test in Airgap Environment**:
   ```bash
   # Pull from ECR
   docker pull <ECR_REGISTRY>/packer-gitlab-cicd:latest

   # Run tests
   ./test-container.sh <ECR_REGISTRY>/packer-gitlab-cicd:latest true
   ```

## Additional Testing Scenarios

### Test with Your Actual Packer Templates

The automated tests use minimal templates. Test with your real templates:

```bash
# Navigate to your Packer template directory
cd /path/to/your/packer/templates

# Test packer init
docker run --rm -v "$(pwd):/workspace" packer-gitlab-cicd:test \
  sh -c "cd /workspace && packer init ."

# Test packer validate
docker run --rm -v "$(pwd):/workspace" packer-gitlab-cicd:test \
  sh -c "cd /workspace && packer validate ."

# Test with your variables
docker run --rm -v "$(pwd):/workspace" packer-gitlab-cicd:test \
  sh -c "cd /workspace && packer validate -var-file=vars.pkrvars.hcl ."
```

### Test Ansible Provisioner

If you use Ansible provisioners, test them specifically:

```bash
# Check Ansible can parse your playbook
docker run --rm -v "$(pwd):/workspace" packer-gitlab-cicd:test \
  ansible-playbook --syntax-check /workspace/playbooks/your-playbook.yml

# Check for Python dependencies
docker run --rm packer-gitlab-cicd:test python3 -c "import boto3; print('boto3 available')"
```

If you get `ModuleNotFoundError`, you need to add Python packages to the Dockerfile.

### Test with AWS Credentials (Optional)

If you have AWS credentials and want to test actual AWS operations:

```bash
# Test AWS CLI with credentials
docker run --rm \
  -e AWS_ACCESS_KEY_ID=your-key \
  -e AWS_SECRET_ACCESS_KEY=your-secret \
  -e AWS_DEFAULT_REGION=us-east-1 \
  packer-gitlab-cicd:test \
  aws sts get-caller-identity

# Or mount AWS credentials
docker run --rm \
  -v ~/.aws:/root/.aws:ro \
  packer-gitlab-cicd:test \
  aws s3 ls
```

**Note**: This requires internet access and valid AWS credentials.

## Checklist for Airgap Readiness

Before transferring to airgapped environment, verify:

- [ ] `./collect-dependencies.sh` completed successfully
- [ ] `packer-base-1.14.2.tar` file exists (several hundred MB)
- [ ] `dependencies/pip-packages/` contains AWS CLI wheels
- [ ] `dependencies/packer-plugins/packer-plugin-ansible.zip` exists
- [ ] Docker build completes without errors
- [ ] Automated test script passes (≥80%)
- [ ] Airgap simulation test passes
- [ ] Tested with your actual Packer templates
- [ ] All required Packer plugins are included
- [ ] All required Python packages for Ansible are installed

## Help & Troubleshooting

- **Detailed testing guide**: See [TESTING_GUIDE.md](./TESTING_GUIDE.md)
- **Project README**: See [README.md](./README.md)
- **Test script source**: See [test-container.sh](./test-container.sh)

## Pro Tips

1. **Save test output**: Redirect to file for review
   ```bash
   ./test-container.sh packer-gitlab-cicd:test 2>&1 | tee test-results.log
   ```

2. **Test different versions**: Build with different tags
   ```bash
   docker build -t packer-gitlab-cicd:v1.0 .
   ./test-container.sh packer-gitlab-cicd:v1.0
   ```

3. **Clean testing**: Remove container after each test
   ```bash
   docker run --rm ...  # The --rm flag auto-removes container
   ```

4. **Debug failures**: Run interactive shell when tests fail
   ```bash
   docker run -it packer-gitlab-cicd:test sh
   # Then manually run commands to debug
   ```

## Time Estimates

- **Dependency collection**: 2-5 minutes (internet speed dependent)
- **Docker build**: 2-3 minutes
- **Automated tests**: 30-60 seconds
- **Airgap tests**: 45-90 seconds
- **Total**: ~10 minutes for complete validation

## Summary Commands

```bash
# Complete test workflow (copy-paste friendly)
./collect-dependencies.sh && \
docker load < packer-base-1.14.2.tar && \
docker build --platform linux/amd64 -t packer-gitlab-cicd:test . && \
./test-container.sh packer-gitlab-cicd:test true

# If all passes, create bundle
tar -czf packer-airgap-bundle.tar.gz packer-base-1.14.2.tar dependencies/ Dockerfile build-and-push.sh .env.example

# Check bundle
ls -lh packer-airgap-bundle.tar.gz
```

Done! You're ready for airgapped deployment.
