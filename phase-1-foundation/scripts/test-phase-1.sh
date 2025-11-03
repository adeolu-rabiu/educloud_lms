#!/bin/bash

# ============================================
# Phase 1 - Infrastructure Testing Script
# ============================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "========================================"
echo "Phase 1 - Infrastructure Tests"
echo "========================================"
echo -e "${NC}"

TESTS_PASSED=0
TESTS_FAILED=0

# Test function
run_test() {
    local test_name=$1
    local test_command=$2
    
    echo -e "\n${YELLOW}Testing: $test_name${NC}"
    
    if eval "$test_command"; then
        echo -e "${GREEN}✓ PASSED${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Change to terraform directory
cd "$(dirname "$0")/../terraform/environments/dev" 2>/dev/null || {
    echo -e "${RED}Error: Cannot find terraform directory${NC}"
    echo "Please run this script from phase-1-foundation directory"
    exit 1
}

echo ""
echo "Running infrastructure tests..."
echo ""

# Test 1: Terraform/Terragrunt is initialized
run_test "Terraform Initialized" "test -d .terraform || test -d .terragrunt-cache"

# Test 2: Can run terragrunt plan
run_test "Terragrunt Plan" "terragrunt plan -detailed-exitcode > /dev/null 2>&1 || test $? -eq 2"

# Test 3: Check if state file exists
run_test "State File Exists" "terragrunt state list > /dev/null 2>&1"

# Test 4: Validate terraform configuration
run_test "Terraform Validation" "terragrunt validate > /dev/null 2>&1"

# Test 5: Check outputs are available
run_test "Terraform Outputs Available" "terragrunt output > /dev/null 2>&1"

# If using AWS (not LocalStack), run these tests
if aws sts get-caller-identity > /dev/null 2>&1; then
    echo -e "\n${BLUE}Running AWS-specific tests...${NC}"
    
    # Test 6: Check VPC exists
    run_test "VPC Exists" "aws ec2 describe-vpcs --filters 'Name=tag:Project,Values=educloud' --query 'Vpcs[0].VpcId' --output text | grep -q vpc-"
    
    # Test 7: Check subnets exist
    run_test "Subnets Exist" "aws ec2 describe-subnets --filters 'Name=tag:Environment,Values=dev' --query 'Subnets' --output json | jq -e 'length > 0' > /dev/null"
    
    # Test 8: Check security groups exist
    run_test "Security Groups Exist" "aws ec2 describe-security-groups --filters 'Name=tag:Project,Values=educloud' --query 'SecurityGroups' --output json | jq -e 'length > 0' > /dev/null"
    
    # Test 9: Check Internet Gateway exists
    run_test "Internet Gateway Exists" "aws ec2 describe-internet-gateways --filters 'Name=tag:Project,Values=educloud' --query 'InternetGateways' --output json | jq -e 'length > 0' > /dev/null"
fi

# Summary
echo ""
echo "========================================"
echo "Test Summary:"
echo "========================================"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo ""
    echo "Your Phase 1 infrastructure is properly deployed."
    echo ""
    echo "Next steps:"
    echo "1. Review outputs: terragrunt output"
    echo "2. Commit your changes to Git"
    echo "3. Move to Phase 2: Core Applications"
    exit 0
else
    echo -e "${RED}✗ Some tests failed.${NC}"
    echo ""
    echo "Please review the errors above and fix issues."
    echo "You can run 'terragrunt plan' for more details."
    exit 1
fi
