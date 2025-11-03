#!/bin/bash

# ============================================
# EduCloud Platform - Prerequisites Checker
# ============================================
# This script verifies all required tools are installed

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "========================================"
echo "EduCloud Platform - Prerequisites Check"
echo "========================================"
echo -e "${NC}"

MISSING_TOOLS=()
VERSION_WARNINGS=()

# Function to check if a command exists
check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is installed"
        return 0
    else
        echo -e "${RED}✗${NC} $1 is NOT installed"
        MISSING_TOOLS+=("$1")
        return 1
    fi
}

# Function to check version
check_version() {
    local tool=$1
    local current=$2
    local required=$3
    
    if [ "$(printf '%s\n' "$required" "$current" | sort -V | head -n1)" = "$required" ]; then
        echo -e "  ${GREEN}Version: $current (✓ >= $required)${NC}"
    else
        echo -e "  ${YELLOW}Version: $current (⚠ Recommended: >= $required)${NC}"
        VERSION_WARNINGS+=("$tool: Recommended version is >= $required, found $current")
    fi
}

echo "Checking required tools..."
echo ""

# Check Docker
echo "1. Checking Docker..."
if check_command docker; then
    DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+' | head -1)
    check_version "docker" "$DOCKER_VERSION" "24.0"
else
    echo -e "${YELLOW}   Install: curl -fsSL https://get.docker.com | sh${NC}"
fi
echo ""

# Check Docker Compose
echo "2. Checking Docker Compose..."
if check_command docker-compose; then
    COMPOSE_VERSION=$(docker-compose --version | grep -oP '\d+\.\d+' | head -1)
    check_version "docker-compose" "$COMPOSE_VERSION" "2.0"
else
    echo -e "${YELLOW}   Install: See SETUP_GUIDE.md Step 1.3${NC}"
fi
echo ""

# Check Terraform
echo "3. Checking Terraform..."
if check_command terraform; then
    TERRAFORM_VERSION=$(terraform --version | grep -oP 'Terraform v\K\d+\.\d+' | head -1)
    check_version "terraform" "$TERRAFORM_VERSION" "1.6"
else
    echo -e "${YELLOW}   Install: See SETUP_GUIDE.md Step 1.4${NC}"
fi
echo ""

# Check Terragrunt
echo "4. Checking Terragrunt..."
if check_command terragrunt; then
    TERRAGRUNT_VERSION=$(terragrunt --version 2>&1 | grep -oP 'terragrunt version v\K\d+\.\d+' | head -1)
    if [ -n "$TERRAGRUNT_VERSION" ]; then
        check_version "terragrunt" "$TERRAGRUNT_VERSION" "0.54"
    else
        echo -e "  ${GREEN}Version: Installed${NC}"
    fi
else
    echo -e "${YELLOW}   Install: See SETUP_GUIDE.md Step 1.5${NC}"
fi
echo ""

# Check Git
echo "5. Checking Git..."
if check_command git; then
    GIT_VERSION=$(git --version | grep -oP '\d+\.\d+' | head -1)
    check_version "git" "$GIT_VERSION" "2.30"
else
    echo -e "${YELLOW}   Install: sudo apt install git${NC}"
fi
echo ""

# Check curl
echo "6. Checking curl..."
check_command curl || echo -e "${YELLOW}   Install: sudo apt install curl${NC}"
echo ""

# Check jq
echo "7. Checking jq..."
check_command jq || echo -e "${YELLOW}   Install: sudo apt install jq (optional)${NC}"
echo ""

# Check Python3
echo "8. Checking Python3..."
if check_command python3; then
    PYTHON_VERSION=$(python3 --version | grep -oP '\d+\.\d+' | head -1)
    check_version "python3" "$PYTHON_VERSION" "3.8"
else
    echo -e "${YELLOW}   Install: sudo apt install python3${NC}"
fi
echo ""

# Check kubectl (optional)
echo "9. Checking kubectl (optional)..."
if check_command kubectl; then
    KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null | grep -oP 'Client Version: v\K\d+\.\d+' | head -1 || echo "unknown")
    if [ "$KUBECTL_VERSION" != "unknown" ]; then
        check_version "kubectl" "$KUBECTL_VERSION" "1.28"
    else
        echo -e "  ${GREEN}Version: Installed${NC}"
    fi
else
    echo -e "${YELLOW}   kubectl is optional (needed for Phase 5)${NC}"
fi
echo ""

# Check AWS CLI (optional)
echo "10. Checking AWS CLI (optional)..."
if check_command aws; then
    AWS_VERSION=$(aws --version 2>&1 | grep -oP 'aws-cli/\K\d+\.\d+' | head -1)
    check_version "aws" "$AWS_VERSION" "2.0"
else
    echo -e "${YELLOW}   AWS CLI is optional (use LocalStack for local dev)${NC}"
fi
echo ""

echo "========================================"
echo "System Information:"
echo "========================================"
echo "OS: $(uname -s)"
echo "Architecture: $(uname -m)"
echo "Kernel: $(uname -r)"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "Distribution: $NAME $VERSION"
fi
echo ""

echo "========================================"
echo "Docker Check:"
echo "========================================"

if command -v docker &> /dev/null; then
    if docker ps &> /dev/null; then
        echo -e "${GREEN}✓${NC} Docker daemon is running"
        echo ""
        echo "Docker info:"
        docker info 2>/dev/null | grep -E "Server Version|Storage Driver|Containers|Images" || echo "Docker info not available"
    else
        echo -e "${RED}✗${NC} Docker daemon is NOT running"
        echo ""
        echo "Start Docker with:"
        echo "  sudo systemctl start docker"
        echo "  sudo systemctl enable docker"
        MISSING_TOOLS+=("docker-daemon")
    fi
else
    echo -e "${RED}✗${NC} Docker is not installed"
fi
echo ""

echo "========================================"
echo "User Permissions:"
echo "========================================"

if groups | grep -q docker; then
    echo -e "${GREEN}✓${NC} Current user is in 'docker' group"
else
    echo -e "${YELLOW}⚠${NC} Current user is NOT in 'docker' group"
    echo ""
    echo "Add user to docker group with:"
    echo "  sudo usermod -aG docker \$USER"
    echo "  Then logout and login again"
    VERSION_WARNINGS+=("User not in docker group - will need sudo for docker commands")
fi
echo ""

echo "========================================"
echo "Summary:"
echo "========================================"

if [ ${#MISSING_TOOLS[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ All required tools are installed!${NC}"
    echo ""
    echo -e "${GREEN}You're ready to proceed with setup!${NC}"
else
    echo -e "${RED}✗ Missing required tools (${#MISSING_TOOLS[@]}):${NC}"
    for tool in "${MISSING_TOOLS[@]}"; do
        echo "  - $tool"
    done
    echo ""
    echo "Please install missing tools before proceeding."
    echo "See SETUP_GUIDE.md for installation instructions."
fi

if [ ${#VERSION_WARNINGS[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Version Warnings:${NC}"
    for warning in "${VERSION_WARNINGS[@]}"; do
        echo "  - $warning"
    done
fi

echo ""
echo "========================================"
echo "Next Steps:"
echo "========================================"
if [ ${#MISSING_TOOLS[@]} -eq 0 ]; then
    echo "1. Run: ./scripts/setup-project.sh"
    echo "2. Follow SETUP_GUIDE.md for Phase 1"
else
    echo "1. Install missing tools (see above)"
    echo "2. Run this script again to verify"
    echo "3. Then run: ./scripts/setup-project.sh"
fi
echo ""

if [ ${#MISSING_TOOLS[@]} -eq 0 ]; then
    exit 0
else
    exit 1
fi
