#!/bin/bash
set -e

# Script to build and push the enhanced Packer image in airgap environment
# Prerequisites:
#   - AWS CLI configured with ECR access
#   - packer-base-1.14.2.tar loaded into Docker
#   - dependencies/ folder extracted from bundle

# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Required environment variables
: ${AWS_REGION:?'AWS_REGION not set'}
: ${ECR_REGISTRY:?'ECR_REGISTRY not set'}
: ${CICD_IMAGE_NAME:='packer-gitlab-cicd'}
: ${IMAGE_TAG:='latest'}

FULL_IMAGE_NAME="${ECR_REGISTRY}/${CICD_IMAGE_NAME}:${IMAGE_TAG}"

echo "=== Packer CI/CD Image Build and Push ==="
echo "Target: ${FULL_IMAGE_NAME}"
echo ""

# Verify dependencies exist
if [ ! -f "dependencies/binaries/awscliv2.zip" ]; then
    echo "ERROR: dependencies/binaries/awscliv2.zip not found"
    echo "Make sure you've extracted the bundle and dependencies are present"
    exit 1
fi

# ECR login
echo "Logging into ECR..."
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin ${ECR_REGISTRY}

# Build image
echo "Building enhanced Packer image..."
docker build --platform linux/amd64 -t ${CICD_IMAGE_NAME}:${IMAGE_TAG} .

# Tag for ECR
echo "Tagging image..."
docker tag ${CICD_IMAGE_NAME}:${IMAGE_TAG} ${FULL_IMAGE_NAME}

# Push to ECR
echo "Pushing to ECR..."
docker push ${FULL_IMAGE_NAME}

echo ""
echo "=== Build and Push Complete ==="
echo "Image available at: ${FULL_IMAGE_NAME}"
echo ""
echo "Use in GitLab CI with:"
echo "  image: ${FULL_IMAGE_NAME}"
