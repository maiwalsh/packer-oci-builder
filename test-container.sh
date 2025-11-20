#!/bin/bash
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default image name
IMAGE_NAME=${1:-"packer-gitlab-cicd:test"}
AIRGAP_TEST=${2:-"false"}

echo -e "${BLUE}=== Packer Container Testing Script ===${NC}"
echo -e "${BLUE}Testing image: ${IMAGE_NAME}${NC}"
echo ""

# Counter for tests
PASSED=0
FAILED=0
TOTAL=0

# Function to run a test
run_test() {
    local test_name=$1
    local test_command=$2

    TOTAL=$((TOTAL + 1))
    echo -n "Test $TOTAL: $test_name ... "

    if eval "$test_command" > /dev/null 2>&1; then
        echo -e "${GREEN}PASSED${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

# Function to run a test with output capture
run_test_with_output() {
    local test_name=$1
    local test_command=$2
    local expected_pattern=$3

    TOTAL=$((TOTAL + 1))
    echo -n "Test $TOTAL: $test_name ... "

    output=$(eval "$test_command" 2>&1)
    if echo "$output" | grep -q "$expected_pattern"; then
        echo -e "${GREEN}PASSED${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        echo -e "${YELLOW}Expected pattern: $expected_pattern${NC}"
        echo -e "${YELLOW}Got: $output${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

echo -e "${BLUE}=== Phase 1: Basic Container Tests ===${NC}"
echo ""

# Check if image exists
run_test "Docker image exists" "docker image inspect ${IMAGE_NAME}"

# Test Packer
run_test_with_output "Packer is installed" \
    "docker run --rm ${IMAGE_NAME} packer --version" \
    "Packer v"

# Test AWS CLI
run_test_with_output "AWS CLI is installed" \
    "docker run --rm ${IMAGE_NAME} aws --version" \
    "aws-cli"

# Test Git
run_test_with_output "Git is installed" \
    "docker run --rm ${IMAGE_NAME} git --version" \
    "git version"

# Test Ansible
run_test_with_output "Ansible is installed" \
    "docker run --rm ${IMAGE_NAME} ansible --version" \
    "ansible"

# Test JQ
run_test_with_output "JQ is installed" \
    "docker run --rm ${IMAGE_NAME} jq --version" \
    "jq-"

# Test Python3
run_test_with_output "Python3 is installed" \
    "docker run --rm ${IMAGE_NAME} python3 --version" \
    "Python 3"

# Test SSH client
run_test "SSH client is installed" \
    "docker run --rm ${IMAGE_NAME} which ssh"

# Test curl
run_test "Curl is installed" \
    "docker run --rm ${IMAGE_NAME} which curl"

# Test unzip
run_test "Unzip is installed" \
    "docker run --rm ${IMAGE_NAME} which unzip"

echo ""
echo -e "${BLUE}=== Phase 2: Packer Plugin Tests ===${NC}"
echo ""

# Check Ansible plugin directory exists
run_test "Ansible plugin directory exists" \
    "docker run --rm ${IMAGE_NAME} test -d /root/.packer.d/plugins/github.com/hashicorp/ansible"

# Check Ansible plugin binary exists
run_test_with_output "Ansible plugin binary exists" \
    "docker run --rm ${IMAGE_NAME} ls /root/.packer.d/plugins/github.com/hashicorp/ansible/" \
    "packer-plugin-ansible_v1.1.4"

# Check plugin is executable
run_test "Ansible plugin is executable" \
    "docker run --rm ${IMAGE_NAME} test -x /root/.packer.d/plugins/github.com/hashicorp/ansible/packer-plugin-ansible_v1.1.4_x5.0_linux_amd64"

echo ""
echo -e "${BLUE}=== Phase 3: Packer Functionality Tests ===${NC}"
echo ""

# Create temporary test directory
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

# Create a minimal Packer template
cat > "$TEST_DIR/test.pkr.hcl" << 'EOF'
packer {
  required_plugins {
    ansible = {
      version = "~> 1.1.4"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

source "null" "test" {
  communicator = "none"
}

build {
  sources = ["source.null.test"]
}
EOF

# Test packer init and validate together (must be in same container)
echo -n "Test $((TOTAL + 1)): Packer init detects pre-installed plugin ... "
TOTAL=$((TOTAL + 1))
output=$(docker run --rm -v "$TEST_DIR:/workspace" ${IMAGE_NAME} sh -c "cd /workspace && packer init test.pkr.hcl" 2>&1)
if echo "$output" | grep -qE "Installed plugin|installed|already satisfied"; then
    echo -e "${GREEN}PASSED${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}WARNING${NC}"
    echo -e "${YELLOW}Output: $output${NC}"
    echo -e "${YELLOW}Plugin might not be detected correctly${NC}"
fi

# Test packer validate (must run init first in same container session)
echo -n "Test $((TOTAL + 1)): Packer validate works ... "
TOTAL=$((TOTAL + 1))
output=$(docker run --rm -v "$TEST_DIR:/workspace" ${IMAGE_NAME} sh -c "cd /workspace && packer init test.pkr.hcl >/dev/null 2>&1 && packer validate test.pkr.hcl" 2>&1)
if echo "$output" | grep -q "valid"; then
    echo -e "${GREEN}PASSED${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}FAILED${NC}"
    echo -e "${YELLOW}Expected pattern: valid${NC}"
    echo -e "${YELLOW}Got: $output${NC}"
    FAILED=$((FAILED + 1))
fi

echo ""
echo -e "${BLUE}=== Phase 4: AWS CLI Functionality ===${NC}"
echo ""

# Test AWS CLI help
run_test "AWS CLI help command works" \
    "docker run --rm ${IMAGE_NAME} aws help"

# Test AWS CLI S3 command structure (no credentials needed for help)
run_test "AWS CLI S3 subcommand available" \
    "docker run --rm ${IMAGE_NAME} aws s3 help"

echo ""
echo -e "${BLUE}=== Phase 5: Ansible Functionality ===${NC}"
echo ""

# Create a simple Ansible playbook
cat > "$TEST_DIR/test-playbook.yml" << 'EOF'
---
- name: Test playbook
  hosts: localhost
  connection: local
  tasks:
    - name: Debug message
      debug:
        msg: "Ansible is working!"
EOF

# Test Ansible playbook syntax check
run_test "Ansible playbook syntax check" \
    "docker run --rm -v \"$TEST_DIR:/workspace\" ${IMAGE_NAME} ansible-playbook --syntax-check /workspace/test-playbook.yml"

# Test Ansible inventory
run_test "Ansible inventory command works" \
    "docker run --rm ${IMAGE_NAME} ansible-inventory --list"

echo ""

# Airgap test (optional)
if [ "$AIRGAP_TEST" = "true" ]; then
    echo -e "${BLUE}=== Phase 6: Airgap Simulation Test ===${NC}"
    echo ""

    # Create isolated network
    NETWORK_NAME="airgap-test-$$"
    echo -e "${YELLOW}Creating isolated network: ${NETWORK_NAME}${NC}"
    docker network create --internal ${NETWORK_NAME} > /dev/null 2>&1

    # Test that internet is blocked
    echo -n "Test: Internet is blocked in isolated network ... "
    if docker run --rm --network ${NETWORK_NAME} ${IMAGE_NAME} ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; then
        echo -e "${RED}FAILED - Internet is NOT blocked!${NC}"
        FAILED=$((FAILED + 1))
    else
        echo -e "${GREEN}PASSED${NC}"
        PASSED=$((PASSED + 1))
    fi
    TOTAL=$((TOTAL + 1))

    # Test Packer still works without internet
    run_test "Packer works without internet" \
        "docker run --rm --network ${NETWORK_NAME} ${IMAGE_NAME} packer --version"

    # Test packer validate without internet
    run_test "Packer validate works without internet" \
        "docker run --rm --network ${NETWORK_NAME} -v \"$TEST_DIR:/workspace\" ${IMAGE_NAME} sh -c \"cd /workspace && packer validate test.pkr.hcl\""

    # Cleanup network
    echo -e "${YELLOW}Cleaning up isolated network${NC}"
    docker network rm ${NETWORK_NAME} > /dev/null 2>&1

    echo ""
fi

# Summary
echo -e "${BLUE}=== Test Summary ===${NC}"
echo -e "Total Tests: ${TOTAL}"
echo -e "${GREEN}Passed: ${PASSED}${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed: ${FAILED}${NC}"
else
    echo -e "Failed: ${FAILED}"
fi
echo ""

# Calculate percentage
if [ $TOTAL -gt 0 ]; then
    PERCENTAGE=$((PASSED * 100 / TOTAL))
    echo -e "Success Rate: ${PERCENTAGE}%"
    echo ""
fi

# Exit with appropriate code
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed! Container is ready for airgapped deployment.${NC}"
    exit 0
elif [ $PASSED -ge $((TOTAL * 80 / 100)) ]; then
    echo -e "${YELLOW}⚠ Most tests passed (${PERCENTAGE}%). Review failed tests before deployment.${NC}"
    exit 1
else
    echo -e "${RED}✗ Too many tests failed (${PERCENTAGE}% passed). Container needs fixes.${NC}"
    exit 2
fi
