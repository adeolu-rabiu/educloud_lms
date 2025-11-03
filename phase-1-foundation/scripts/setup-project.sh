#!/bin/bash

# ============================================
# EduCloud Platform - Project Setup Script
# ============================================
# Initializes the project and prepares for development

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${BLUE}"
cat << "EOF"
 ___________            __________.__                   .___
 \_   _____/  ____   __ \_   ___ \  |    ____   __ __  __| _/
  |    __)_ / ___\ |  ||    \  \/|  |   /  _ \ |  |  \/ __ | 
  |        \\  \___|  ||     \___|  |__(  <_> )|  |  / /_/ | 
 /_______  /\___  |__| \______  /____/ \____/ |____/\____ | 
         \/     \/            \/                          \/ 
  _________    _____________________ _________      _____   
 /   _____/   /  _  \__    ___/\__  \\_   ___ \   _/ ____\  
 \_____  \   /  /_\  \|    |    /  _/    \  \/   \   __\    
 /        \ /    |    \    |    \  \\_\  \        |  |      
/_______  / \____|__  /____|     \_____/  \_____  |__|      
        \/          \/                           \/          
EOF
echo -e "${NC}"

echo "========================================"
echo "EduCloud Platform - Project Setup"
echo "========================================"
echo ""

# Check if running from project root
if [ ! -f "$PROJECT_ROOT/README.md" ]; then
    echo -e "${YELLOW}Warning: Please run this script from the project root${NC}"
    echo "Current directory: $(pwd)"
    echo "Expected: ~/projects/educloud-platform"
    echo ""
    read -p "Continue anyway? [y/N]: " continue_setup
    if [ "$continue_setup" != "y" ] && [ "$continue_setup" != "Y" ]; then
        exit 1
    fi
fi

cd "$PROJECT_ROOT"

echo "Project root: $PROJECT_ROOT"
echo ""

# Step 1: Run prerequisites check
echo -e "${GREEN}Step 1: Checking prerequisites...${NC}"
if [ -f "./scripts/check-prerequisites.sh" ]; then
    bash ./scripts/check-prerequisites.sh
    if [ $? -ne 0 ]; then
        echo ""
        echo -e "${YELLOW}Please install missing dependencies before continuing${NC}"
        read -p "Continue setup anyway? [y/N]: " continue_anyway
        if [ "$continue_anyway" != "y" ] && [ "$continue_anyway" != "Y" ]; then
            exit 1
        fi
    fi
else
    echo -e "${YELLOW}Prerequisites check script not found, skipping...${NC}"
fi

echo ""
echo -e "${GREEN}Step 2: Setting up environment files...${NC}"

# Create .env file if it doesn't exist
if [ ! -f ".env" ]; then
    cat > .env << 'ENVFILE'
# EduCloud Platform Environment Configuration

# Project Settings
PROJECT_NAME=educloud
ENVIRONMENT=dev

# AWS Configuration (for LocalStack or real AWS)
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=123456789012

# Database Configuration
POSTGRES_USER=educloud
POSTGRES_PASSWORD=dev_password_change_in_production
POSTGRES_DB=educloud_dev

MONGODB_USER=educloud
MONGODB_PASSWORD=dev_password_change_in_production
MONGODB_DB=educloud_events

# Redis Configuration
REDIS_PASSWORD=

# Application Configuration
RAILS_ENV=development
NODE_ENV=development

# API Keys (add your keys here)
SECRET_KEY_BASE=change_this_in_production
JWT_SECRET=change_this_in_production

# Monitoring (optional for local development)
NEW_RELIC_LICENSE_KEY=
DATADOG_API_KEY=

# Grafana
GRAFANA_PASSWORD=admin

# Feature Flags
ENABLE_CACHING=true
ENABLE_BACKGROUND_JOBS=true
ENVFILE
    echo "✓ Created .env file"
    echo -e "  ${YELLOW}IMPORTANT: Update .env with your actual credentials!${NC}"
else
    echo "✓ .env file already exists"
fi
echo ""

# Create .env.example
if [ ! -f ".env.example" ]; then
    cat > .env.example << 'ENVEXAMPLE'
# EduCloud Platform Environment Configuration Example
# Copy this file to .env and update with your values

PROJECT_NAME=educloud
ENVIRONMENT=dev

AWS_REGION=us-east-1
AWS_ACCOUNT_ID=your_aws_account_id

POSTGRES_USER=educloud
POSTGRES_PASSWORD=your_secure_password
POSTGRES_DB=educloud_dev

MONGODB_USER=educloud
MONGODB_PASSWORD=your_secure_password
MONGODB_DB=educloud_events

RAILS_ENV=development
NODE_ENV=development

SECRET_KEY_BASE=generate_with_openssl_rand_hex_64
JWT_SECRET=generate_with_openssl_rand_hex_64

GRAFANA_PASSWORD=your_grafana_password
ENVEXAMPLE
    echo "✓ Created .env.example"
fi

echo ""
echo -e "${GREEN}Step 3: Creating directory structure...${NC}"

# Ensure all directories exist
mkdir -p logs secrets tmp outputs
mkdir -p scripts
mkdir -p phase-1-foundation/{terraform/{modules/{networking,security,compute},environments/{dev,staging,prod},backend-setup},scripts,docs,tests}
mkdir -p phase-2-core-services/{applications/{rails-api,node-service},scripts,tests}
mkdir -p phase-3-caching-queues/{scripts,tests}
mkdir -p phase-4-search-analytics/{scripts,tests}
mkdir -p phase-5-multi-cloud-edge/{scripts,tests}
mkdir -p phase-6-cicd/{scripts,tests}
mkdir -p phase-7-monitoring/{scripts,tests}

echo "✓ Directory structure created"
echo ""

echo -e "${GREEN}Step 4: Setting up Git repository...${NC}"

if [ ! -d ".git" ]; then
    git init
    echo "✓ Git repository initialized"
    
    # Create initial .gitignore if it doesn't exist
    if [ ! -f ".gitignore" ]; then
        cat > .gitignore << 'GITIGNORE'
# Environment files
.env
.env.*
!.env.example

# Terraform
*.tfstate
*.tfstate.*
.terraform/
.terragrunt-cache/
terraform.tfvars

# Secrets
secrets/
*.pem
*.key

# Logs
logs/
*.log

# OS
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/

# Dependencies
node_modules/
vendor/bundle/

# Docker
docker-compose.override.yml

# Temporary
tmp/
*.tmp
GITIGNORE
        echo "✓ Created basic .gitignore"
    fi
    
    # Create pre-commit hook
    mkdir -p .git/hooks
    cat > .git/hooks/pre-commit << 'HOOK'
#!/bin/bash
# Pre-commit hook to prevent committing sensitive files

FORBIDDEN_FILES=(
    ".env"
    "*.tfvars"
    "*terraform.tfstate*"
    "*.pem"
    "*.key"
    "*_rsa"
    "*_dsa"
)

for pattern in "${FORBIDDEN_FILES[@]}"; do
    if git diff --cached --name-only | grep -E "$pattern"; then
        echo "Error: Attempting to commit sensitive file matching: $pattern"
        echo "Please review and remove from staging area"
        exit 1
    fi
done

# Check for hardcoded credentials
if git diff --cached | grep -iE '(password|secret|api[_-]?key).*=.*["'\''][^"'\'']+["'\'']'; then
    echo "Warning: Potential hardcoded credentials detected"
    echo "Please review your changes"
    read -p "Continue with commit? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
HOOK
    chmod +x .git/hooks/pre-commit
    echo "✓ Pre-commit hooks installed"
    
    # Initial commit
    git add .gitignore README.md 2>/dev/null || true
    git commit -m "Initial commit: Project structure" 2>/dev/null || echo "  (No files to commit yet)"
else
    echo "✓ Git repository already initialized"
fi
echo ""

echo -e "${GREEN}Step 5: Making scripts executable...${NC}"

find ./scripts -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
find ./phase-*/scripts -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
find ./phase-*/tests -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

echo "✓ Scripts are now executable"
echo ""

echo -e "${GREEN}Step 6: Generating SSH key for bastion (optional)...${NC}"

if [ ! -f "./secrets/bastion_key" ]; then
    read -p "Generate SSH key for bastion host? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mkdir -p ./secrets
        ssh-keygen -t rsa -b 4096 -f ./secrets/bastion_key -N "" -C "educloud-bastion"
        chmod 600 ./secrets/bastion_key
        echo "✓ SSH key generated at ./secrets/bastion_key"
    else
        echo "  Skipped SSH key generation"
    fi
else
    echo "✓ SSH key already exists"
fi
echo ""

echo -e "${GREEN}Step 7: Creating helper scripts...${NC}"

# Create a quick-start script
cat > quick-start.sh << 'QUICKSTART'
#!/bin/bash
# Quick start script to launch Phase 2 services

echo "Starting EduCloud Platform services..."
cd phase-2-core-services

if [ ! -f "docker-compose.yml" ]; then
    echo "Error: docker-compose.yml not found"
    echo "Please complete Phase 2 setup first"
    exit 1
fi

docker-compose up -d

echo ""
echo "Services started!"
echo ""
echo "Access:"
echo "  Rails API:     http://localhost:3000"
echo "  Node Service:  http://localhost:8080"
echo "  PostgreSQL:    localhost:5432"
echo "  MongoDB:       localhost:27017"
echo "  Redis:         localhost:6379"
echo ""
echo "Check status: docker-compose ps"
echo "View logs:    docker-compose logs -f"
QUICKSTART
chmod +x quick-start.sh
echo "✓ Created quick-start.sh"

# Create a status check script
cat > check-status.sh << 'STATUS'
#!/bin/bash
# Check status of all services

echo "========================================"
echo "EduCloud Platform - System Status"
echo "========================================"
echo ""

# Check if Docker is running
if docker ps &> /dev/null; then
    echo "✓ Docker is running"
else
    echo "✗ Docker is NOT running"
    exit 1
fi

# Check Phase 2 services if they exist
if [ -f "phase-2-core-services/docker-compose.yml" ]; then
    cd phase-2-core-services
    echo ""
    echo "Phase 2 Services:"
    docker-compose ps
    cd ..
else
    echo ""
    echo "Phase 2 not yet set up"
fi

echo ""
echo "System Resources:"
docker system df

echo ""
echo "For more details:"
echo "  docker stats"
echo "  docker-compose logs [service-name]"
STATUS
chmod +x check-status.sh
echo "✓ Created check-status.sh"
echo ""

echo "========================================"
echo -e "${GREEN}Setup Complete!${NC}"
echo "========================================"
echo ""
echo "Project initialized successfully!"
echo ""
echo -e "${YELLOW}Important Next Steps:${NC}"
echo ""
echo "1. Update environment variables:"
echo "   nano .env"
echo "   ${YELLOW}Change passwords and secrets!${NC}"
echo ""
echo "2. Generate secure secrets:"
echo "   openssl rand -hex 64"
echo "   (Use output for SECRET_KEY_BASE and JWT_SECRET)"
echo ""
echo "3. Configure Git remote (if using GitHub):"
echo "   git remote add origin https://github.com/adeolurabiu/educloud_lms.git"
echo "   git branch -M main"
echo ""
echo "4. Start with Phase 1:"
echo "   cd phase-1-foundation"
echo "   cat README.md"
echo ""
echo "5. Or jump to Phase 2 (local development):"
echo "   cd phase-2-core-services"
echo "   # Create docker-compose.yml first"
echo "   docker-compose up -d"
echo ""
echo "Quick commands:"
echo "  ./quick-start.sh     - Start Phase 2 services"
echo "  ./check-status.sh    - Check system status"
echo ""
echo "Documentation:"
echo "  README.md            - Project overview"
echo "  SETUP_GUIDE.md       - Detailed setup guide"
echo "  COMMANDS.md          - Quick command reference"
echo ""
echo -e "${BLUE}Happy building! 🚀${NC}"
echo ""
