#!/bin/bash

# ============================================
# Phase 1 - Infrastructure Setup Script
# ============================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}"
echo "========================================"
echo "Phase 1 - Infrastructure Setup"
echo "========================================"
echo -e "${NC}"

# Check if we're in the right directory
if [ ! -d "terraform" ]; then
    echo -e "${RED}Error: terraform directory not found${NC}"
    echo "Please run this script from phase-1-foundation directory"
    exit 1
fi

echo ""
echo "This script will help you set up Phase 1 infrastructure."
echo ""

# Load environment variables from .env file
load_env_file() {
    local env_file="$1"
    
    if [ ! -f "$env_file" ]; then
        echo -e "${RED}✗ .env file not found at: $env_file${NC}"
        echo ""
        echo "Please create a .env file with the following variables:"
        echo "  AWS_ACCESS_KEY_ID=your_access_key"
        echo "  AWS_SECRET_ACCESS_KEY=your_secret_key"
        echo "  AWS_DEFAULT_REGION=eu-west-2"
        echo "  AWS_ACCOUNT_ID=your_account_id"
        echo ""
        return 1
    fi
    
    echo -e "${GREEN}✓ Loading environment variables from .env${NC}"
    
    # Export variables from .env file
    set -a
    source "$env_file"
    set +a
    
    return 0
}

# Validate required AWS environment variables
validate_aws_credentials() {
    local missing_vars=()
    
    if [ -z "$AWS_ACCESS_KEY_ID" ]; then
        missing_vars+=("AWS_ACCESS_KEY_ID")
    fi
    
    if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        missing_vars+=("AWS_SECRET_ACCESS_KEY")
    fi
    
    if [ -z "$AWS_DEFAULT_REGION" ]; then
        missing_vars+=("AWS_DEFAULT_REGION")
    fi
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo -e "${RED}✗ Missing required environment variables:${NC}"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        echo ""
        echo "Please add these to your .env file"
        return 1
    fi
    
    echo -e "${GREEN}✓ AWS credentials loaded from .env${NC}"
    echo "  Region: $AWS_DEFAULT_REGION"
    echo "  Access Key: ${AWS_ACCESS_KEY_ID:0:10}***"
    
    return 0
}

# Step 1: Check prerequisites
echo -e "${GREEN}Step 1: Checking prerequisites...${NC}"
if command -v terraform &> /dev/null && command -v terragrunt &> /dev/null; then
    echo "✓ Terraform and Terragrunt are installed"
else
    echo "✗ Terraform or Terragrunt not found"
    echo "Please run: ../../scripts/check-prerequisites.sh"
    exit 1
fi
echo ""

# Step 2: Choose deployment option
echo -e "${GREEN}Step 2: Choose deployment option${NC}"
echo "1) LocalStack (local development, no AWS account needed)"
echo "2) AWS Account (real AWS resources, charges may apply)"
read -p "Enter choice [1-2]: " choice
echo ""

if [ "$choice" = "1" ]; then
    echo "Setting up for LocalStack..."
    export AWS_ACCESS_KEY_ID=test
    export AWS_SECRET_ACCESS_KEY=test
    export AWS_DEFAULT_REGION=eu-west-2
    export AWS_ENDPOINT_URL=http://localhost:4566
    
    # Check if LocalStack is running
    if curl -s http://localhost:4566/_localstack/health > /dev/null 2>&1; then
        echo "✓ LocalStack is running"
    else
        echo "✗ LocalStack is not running"
        echo ""
        echo "Start LocalStack with:"
        echo "  pip3 install localstack"
        echo "  localstack start -d"
        exit 1
    fi
elif [ "$choice" = "2" ]; then
    echo "Using AWS Account..."
    echo ""
    
    # Load credentials from .env file
    ENV_FILE="../../.env"
    
    if [ ! -f "$ENV_FILE" ]; then
        # Try alternative locations
        if [ -f "../.env" ]; then
            ENV_FILE="../.env"
        elif [ -f ".env" ]; then
            ENV_FILE=".env"
        fi
    fi
    
    if ! load_env_file "$ENV_FILE"; then
        exit 1
    fi
    
    echo ""
    
    # Validate credentials
    if ! validate_aws_credentials; then
        exit 1
    fi
    
    echo ""
    
    # Export credentials for Terraform/AWS CLI
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    export AWS_DEFAULT_REGION
    
    # Test AWS connection
    echo "Testing AWS connection..."
    if aws sts get-caller-identity > /dev/null 2>&1; then
        echo -e "${GREEN}✓ AWS credentials verified${NC}"
        echo ""
        aws sts get-caller-identity
    else
        echo -e "${RED}✗ AWS credentials are invalid${NC}"
        echo ""
        echo "Please check your credentials in .env file"
        exit 1
    fi
else
    echo "Invalid choice"
    exit 1
fi
echo ""

# Step 3: Deploy backend
echo -e "${GREEN}Step 3: Deploying Terraform backend...${NC}"
cd terraform/backend-setup

if [ ! -f "main.tf" ]; then
    echo "✗ Backend configuration not found"
    echo "Please create main.tf, variables.tf, and outputs.tf"
    echo "See documentation for examples"
    exit 1
fi

echo "Initializing backend..."
terraform init

echo ""
read -p "Deploy backend (S3 + DynamoDB)? [y/N]: " deploy_backend
if [ "$deploy_backend" = "y" ] || [ "$deploy_backend" = "Y" ]; then
    terraform apply
    echo -e "${GREEN}✓ Backend deployed${NC}"
else
    echo "Skipped backend deployment"
fi

cd ../..
echo ""

# Step 4: Deploy development environment
echo -e "${GREEN}Step 4: Deploying development environment...${NC}"
cd terraform/environments/dev

if [ ! -f "terragrunt.hcl" ]; then
    echo "✗ Terragrunt configuration not found"
    echo "Please create terragrunt.hcl in environments/dev"
    exit 1
fi

echo "Initializing development environment..."
terragrunt init

echo ""
echo "Planning infrastructure..."
terragrunt plan

echo ""
read -p "Apply infrastructure changes? [y/N]: " apply_infra
if [ "$apply_infra" = "y" ] || [ "$apply_infra" = "Y" ]; then
    terragrunt apply
    echo -e "${GREEN}✓ Infrastructure deployed${NC}"
    echo ""
    echo "Infrastructure outputs:"
    terragrunt output
else
    echo "Skipped infrastructure deployment"
fi

cd ../../..
echo ""

# Step 5: Run tests
echo -e "${GREEN}Step 5: Running tests...${NC}"
if [ -f "tests/test-phase-1.sh" ]; then
    chmod +x tests/test-phase-1.sh
    ./tests/test-phase-1.sh
else
    echo "Test script not found, skipping tests"
fi

echo ""
echo "========================================"
echo "Phase 1 Setup Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Review infrastructure outputs"
echo "2. Commit changes to Git"
echo "3. Proceed to Phase 2: cd ../phase-2-core-services"
echo ""
