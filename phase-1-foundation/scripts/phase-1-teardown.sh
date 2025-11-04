#!/bin/bash

# ============================================
# Phase 1 - Infrastructure Teardown Script
# ============================================
# Safely stop or delete Phase 1 AWS resources
# with cost tracking and safety confirmations

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
PROJECT_NAME="educloud"
REGION="${AWS_DEFAULT_REGION:-eu-west-2}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Counters
RESOURCES_FOUND=0
RESOURCES_STOPPED=0
RESOURCES_DELETED=0
COST_SAVINGS=0

# Load environment variables
load_env() {
    if [ -f "$PROJECT_ROOT/.env" ]; then
        echo -e "${GREEN}Loading environment variables...${NC}"
        set -a
        source "$PROJECT_ROOT/.env"
        set +a
    else
        echo -e "${YELLOW}Warning: .env file not found${NC}"
    fi
}

# Print header
print_header() {
    clear
    echo -e "${BLUE}${BOLD}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║         Phase 1 - Infrastructure Teardown Script          ║
║                                                           ║
║         Safely manage Phase 1 AWS resources               ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "${CYAN}Region: ${REGION}${NC}"
    echo -e "${CYAN}Project: ${PROJECT_NAME}${NC}"
    echo ""
}

# Verify AWS credentials
verify_credentials() {
    echo -e "${YELLOW}Verifying AWS credentials...${NC}"
    
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}✗ AWS credentials not configured${NC}"
        echo ""
        echo "Please configure AWS CLI or set credentials in .env file"
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local user_arn=$(aws sts get-caller-identity --query Arn --output text)
    
    echo -e "${GREEN}✓ AWS credentials verified${NC}"
    echo -e "  Account: ${account_id}"
    echo -e "  User: ${user_arn}"
    echo ""
}

# List VPCs
list_vpcs() {
    echo -e "${CYAN}${BOLD}VPCs:${NC}"
    
    local vpcs=$(aws ec2 describe-vpcs \
        --region "$REGION" \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --query 'Vpcs[*].[VpcId,CidrBlock,Tags[?Key==`Environment`].Value|[0],Tags[?Key==`Name`].Value|[0]]' \
        --output text 2>/dev/null)
    
    if [ -z "$vpcs" ]; then
        echo -e "${YELLOW}  No VPCs found${NC}"
    else
        echo "$vpcs" | while read vpc_id cidr env name; do
            echo -e "  ${GREEN}●${NC} VPC: ${vpc_id} (${cidr})"
            echo -e "    Name: ${name}"
            echo -e "    Environment: ${env}"
            ((RESOURCES_FOUND++))
        done
    fi
    echo ""
}

# List EC2 Instances
list_instances() {
    echo -e "${CYAN}${BOLD}EC2 Instances:${NC}"
    
    local instances=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" "Name=instance-state-name,Values=running,stopped" \
        --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`].Value|[0],PublicIpAddress]' \
        --output text 2>/dev/null)
    
    if [ -z "$instances" ]; then
        echo -e "${YELLOW}  No EC2 instances found${NC}"
    else
        echo "$instances" | while read instance_id type state name public_ip; do
            local state_color=$GREEN
            [ "$state" = "stopped" ] && state_color=$YELLOW
            
            echo -e "  ${state_color}●${NC} Instance: ${instance_id}"
            echo -e "    Name: ${name}"
            echo -e "    Type: ${type}"
            echo -e "    State: ${state}"
            echo -e "    Public IP: ${public_ip:-N/A}"
            echo -e "    Cost: ~\$0.29/day (t3.micro)"
            ((RESOURCES_FOUND++))
        done
    fi
    echo ""
}

# List NAT Gateways
list_nat_gateways() {
    echo -e "${CYAN}${BOLD}NAT Gateways:${NC}"
    
    local nat_gateways=$(aws ec2 describe-nat-gateways \
        --region "$REGION" \
        --filter "Name=tag:Project,Values=${PROJECT_NAME}" "Name=state,Values=available,pending,deleting" \
        --query 'NatGateways[*].[NatGatewayId,State,Tags[?Key==`Name`].Value|[0],SubnetId]' \
        --output text 2>/dev/null)
    
    if [ -z "$nat_gateways" ]; then
        echo -e "${YELLOW}  No NAT Gateways found${NC}"
    else
        echo "$nat_gateways" | while read nat_id state name subnet_id; do
            echo -e "  ${GREEN}●${NC} NAT Gateway: ${nat_id}"
            echo -e "    Name: ${name}"
            echo -e "    State: ${state}"
            echo -e "    Subnet: ${subnet_id}"
            echo -e "    Cost: ~\$1.31/day"
            ((RESOURCES_FOUND++))
        done
    fi
    echo ""
}

# List Elastic IPs
list_elastic_ips() {
    echo -e "${CYAN}${BOLD}Elastic IPs:${NC}"
    
    local eips=$(aws ec2 describe-addresses \
        --region "$REGION" \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --query 'Addresses[*].[AllocationId,PublicIp,AssociationId,Tags[?Key==`Name`].Value|[0]]' \
        --output text 2>/dev/null)
    
    if [ -z "$eips" ]; then
        echo -e "${YELLOW}  No Elastic IPs found${NC}"
    else
        echo "$eips" | while read alloc_id public_ip assoc_id name; do
            local status="Unattached"
            [ -n "$assoc_id" ] && status="Attached"
            
            echo -e "  ${GREEN}●${NC} EIP: ${alloc_id}"
            echo -e "    Name: ${name}"
            echo -e "    Public IP: ${public_ip}"
            echo -e "    Status: ${status}"
            [ "$status" = "Unattached" ] && echo -e "    Cost: ~\$0.12/day (unattached)"
            ((RESOURCES_FOUND++))
        done
    fi
    echo ""
}

# List ECS Clusters
list_ecs_clusters() {
    echo -e "${CYAN}${BOLD}ECS Clusters:${NC}"
    
    local clusters=$(aws ecs list-clusters \
        --region "$REGION" \
        --query 'clusterArns[*]' \
        --output text 2>/dev/null)
    
    if [ -z "$clusters" ]; then
        echo -e "${YELLOW}  No ECS clusters found${NC}"
    else
        for cluster_arn in $clusters; do
            local cluster_name=$(basename "$cluster_arn")
            
            if [[ "$cluster_name" == *"$PROJECT_NAME"* ]]; then
                local details=$(aws ecs describe-clusters \
                    --region "$REGION" \
                    --clusters "$cluster_name" \
                    --query 'clusters[0].[clusterName,status,runningTasksCount,activeServicesCount]' \
                    --output text 2>/dev/null)
                
                read name status tasks services <<< "$details"
                
                echo -e "  ${GREEN}●${NC} Cluster: ${name}"
                echo -e "    Status: ${status}"
                echo -e "    Running Tasks: ${tasks}"
                echo -e "    Active Services: ${services}"
                echo -e "    Cost: \$0 (empty cluster)"
                ((RESOURCES_FOUND++))
            fi
        done
    fi
    echo ""
}

# List S3 Buckets
list_s3_buckets() {
    echo -e "${CYAN}${BOLD}S3 Buckets:${NC}"
    
    local buckets=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, '${PROJECT_NAME}')].Name" \
        --output text 2>/dev/null)
    
    if [ -z "$buckets" ]; then
        echo -e "${YELLOW}  No S3 buckets found${NC}"
    else
        for bucket in $buckets; do
            local size=$(aws s3 ls s3://$bucket --recursive --summarize 2>/dev/null | grep "Total Size" | awk '{print $3}')
            local size_mb=$((size / 1024 / 1024))
            
            echo -e "  ${GREEN}●${NC} Bucket: ${bucket}"
            echo -e "    Size: ${size_mb} MB"
            echo -e "    Cost: ~\$0.02/month"
            ((RESOURCES_FOUND++))
        done
    fi
    echo ""
}

# List DynamoDB Tables
list_dynamodb_tables() {
    echo -e "${CYAN}${BOLD}DynamoDB Tables:${NC}"
    
    local tables=$(aws dynamodb list-tables \
        --region "$REGION" \
        --query "TableNames[?contains(@, '${PROJECT_NAME}')]" \
        --output text 2>/dev/null)
    
    if [ -z "$tables" ]; then
        echo -e "${YELLOW}  No DynamoDB tables found${NC}"
    else
        for table in $tables; do
            local details=$(aws dynamodb describe-table \
                --region "$REGION" \
                --table-name "$table" \
                --query 'Table.[TableStatus,ItemCount,TableSizeBytes,BillingModeSummary.BillingMode]' \
                --output text 2>/dev/null)
            
            read status items size billing <<< "$details"
            
            echo -e "  ${GREEN}●${NC} Table: ${table}"
            echo -e "    Status: ${status}"
            echo -e "    Items: ${items}"
            echo -e "    Size: $((size / 1024)) KB"
            echo -e "    Billing: ${billing}"
            echo -e "    Cost: ~\$0.01/month"
            ((RESOURCES_FOUND++))
        done
    fi
    echo ""
}

# List Security Groups
list_security_groups() {
    echo -e "${CYAN}${BOLD}Security Groups:${NC}"
    
    local sgs=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --query 'SecurityGroups[*].[GroupId,GroupName,Description]' \
        --output text 2>/dev/null)
    
    if [ -z "$sgs" ]; then
        echo -e "${YELLOW}  No security groups found${NC}"
    else
        local count=0
        echo "$sgs" | while read sg_id sg_name description; do
            ((count++))
            echo -e "  ${GREEN}●${NC} ${sg_name} (${sg_id})"
        done
        echo -e "  ${CYAN}Total: ${count} security groups${NC}"
        ((RESOURCES_FOUND+=count))
    fi
    echo ""
}

# List CloudWatch Log Groups
list_log_groups() {
    echo -e "${CYAN}${BOLD}CloudWatch Log Groups:${NC}"
    
    local log_groups=$(aws logs describe-log-groups \
        --region "$REGION" \
        --log-group-name-prefix "/ecs/${PROJECT_NAME}" \
        --query 'logGroups[*].[logGroupName,storedBytes,retentionInDays]' \
        --output text 2>/dev/null)
    
    if [ -z "$log_groups" ]; then
        echo -e "${YELLOW}  No log groups found${NC}"
    else
        echo "$log_groups" | while read log_group size retention; do
            local size_mb=$((size / 1024 / 1024))
            echo -e "  ${GREEN}●${NC} Log Group: ${log_group}"
            echo -e "    Size: ${size_mb} MB"
            echo -e "    Retention: ${retention:-Never} days"
            echo -e "    Cost: ~\$0.55/GB/month"
            ((RESOURCES_FOUND++))
        done
    fi
    echo ""
}

# Main list function
list_all_resources() {
    print_header
    echo -e "${BOLD}${BLUE}Scanning for Phase 1 resources in ${REGION}...${NC}"
    echo ""
    
    RESOURCES_FOUND=0
    
    list_vpcs
    list_instances
    list_nat_gateways
    list_elastic_ips
    list_ecs_clusters
    list_s3_buckets
    list_dynamodb_tables
    list_security_groups
    list_log_groups
    
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}Total Resources Found: ${RESOURCES_FOUND}${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Stop EC2 instances
stop_instances() {
    echo -e "${YELLOW}${BOLD}Stopping EC2 Instances...${NC}"
    
    local instances=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" "Name=instance-state-name,Values=running" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text 2>/dev/null)
    
    if [ -z "$instances" ]; then
        echo -e "${YELLOW}  No running instances to stop${NC}"
        return
    fi
    
    for instance_id in $instances; do
        echo -e "  Stopping instance: ${instance_id}"
        aws ec2 stop-instances --region "$REGION" --instance-ids "$instance_id" &> /dev/null
        echo -e "  ${GREEN}✓${NC} Instance stopped"
        echo -e "  ${GREEN}Cost savings: ~\$0.29/day${NC}"
        ((RESOURCES_STOPPED++))
        COST_SAVINGS=$(echo "$COST_SAVINGS + 0.29" | bc)
    done
    
    echo ""
}

# Delete using Terraform/Terragrunt
terraform_destroy() {
    local env=$1
    
    echo -e "${RED}${BOLD}Destroying infrastructure using Terraform...${NC}"
    echo ""
    
    local terraform_dir="$PROJECT_ROOT/phase-1-foundation/terraform"
    
    # Destroy environment
    if [ -d "$terraform_dir/environments/$env" ]; then
        echo -e "${YELLOW}Destroying $env environment...${NC}"
        cd "$terraform_dir/environments/$env"
        
        if [ -f "terragrunt.hcl" ]; then
            echo -e "Running: ${CYAN}terragrunt destroy${NC}"
            terragrunt destroy -auto-approve
        else
            echo -e "Running: ${CYAN}terraform destroy${NC}"
            terraform destroy -auto-approve
        fi
        
        cd - > /dev/null
        echo -e "${GREEN}✓ Environment destroyed${NC}"
        echo ""
    fi
    
    # Destroy backend
    if [ -d "$terraform_dir/backend-setup" ]; then
        echo -e "${YELLOW}Destroying Terraform backend...${NC}"
        cd "$terraform_dir/backend-setup"
        
        echo -e "${RED}WARNING: This will delete the Terraform state bucket!${NC}"
        read -p "Are you sure? Type 'yes' to continue: " confirm
        
        if [ "$confirm" = "yes" ]; then
            # Empty S3 bucket first
            local bucket_name=$(terraform output -raw state_bucket_name 2>/dev/null || echo "")
            if [ -n "$bucket_name" ]; then
                echo -e "  Emptying S3 bucket: ${bucket_name}"
                aws s3 rm "s3://${bucket_name}" --recursive &> /dev/null || true
            fi
            
            terraform destroy -auto-approve
            echo -e "${GREEN}✓ Backend destroyed${NC}"
        else
            echo -e "${YELLOW}Skipped backend destruction${NC}"
        fi
        
        cd - > /dev/null
        echo ""
    fi
}

# Manual resource deletion
manual_delete() {
    echo -e "${RED}${BOLD}Manual Resource Deletion${NC}"
    echo -e "${YELLOW}This will delete resources one by one${NC}"
    echo ""
    
    # Delete NAT Gateways
    echo -e "${CYAN}Deleting NAT Gateways...${NC}"
    local nat_gateways=$(aws ec2 describe-nat-gateways \
        --region "$REGION" \
        --filter "Name=tag:Project,Values=${PROJECT_NAME}" "Name=state,Values=available" \
        --query 'NatGateways[*].NatGatewayId' \
        --output text 2>/dev/null)
    
    for nat_id in $nat_gateways; do
        echo -e "  Deleting NAT Gateway: ${nat_id}"
        aws ec2 delete-nat-gateway --region "$REGION" --nat-gateway-id "$nat_id"
        echo -e "  ${GREEN}✓${NC} NAT Gateway deletion initiated"
        echo -e "  ${GREEN}Cost savings: ~\$1.31/day${NC}"
        ((RESOURCES_DELETED++))
        COST_SAVINGS=$(echo "$COST_SAVINGS + 1.31" | bc)
    done
    
    # Wait for NAT Gateways to delete
    if [ -n "$nat_gateways" ]; then
        echo -e "  ${YELLOW}Waiting for NAT Gateways to delete (this may take 5-10 minutes)...${NC}"
        sleep 30
    fi
    
    # Terminate EC2 Instances
    echo -e "${CYAN}Terminating EC2 Instances...${NC}"
    local instances=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" "Name=instance-state-name,Values=running,stopped" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text 2>/dev/null)
    
    for instance_id in $instances; do
        echo -e "  Terminating instance: ${instance_id}"
        aws ec2 terminate-instances --region "$REGION" --instance-ids "$instance_id" &> /dev/null
        echo -e "  ${GREEN}✓${NC} Instance terminated"
        ((RESOURCES_DELETED++))
    done
    
    # Release Elastic IPs
    echo -e "${CYAN}Releasing Elastic IPs...${NC}"
    local eips=$(aws ec2 describe-addresses \
        --region "$REGION" \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --query 'Addresses[*].AllocationId' \
        --output text 2>/dev/null)
    
    for alloc_id in $eips; do
        echo -e "  Releasing EIP: ${alloc_id}"
        aws ec2 release-address --region "$REGION" --allocation-id "$alloc_id" &> /dev/null || true
        echo -e "  ${GREEN}✓${NC} EIP released"
        ((RESOURCES_DELETED++))
    done
    
    echo ""
    echo -e "${YELLOW}Note: VPC, Subnets, and Security Groups should be deleted via Terraform${NC}"
}

# Delete ECS Clusters
delete_ecs_clusters() {
    echo -e "${CYAN}Deleting ECS Clusters...${NC}"
    
    local clusters=$(aws ecs list-clusters \
        --region "$REGION" \
        --query 'clusterArns[*]' \
        --output text 2>/dev/null)
    
    for cluster_arn in $clusters; do
        local cluster_name=$(basename "$cluster_arn")
        
        if [[ "$cluster_name" == *"$PROJECT_NAME"* ]]; then
            echo -e "  Deleting cluster: ${cluster_name}"
            aws ecs delete-cluster --region "$REGION" --cluster "$cluster_name" &> /dev/null
            echo -e "  ${GREEN}✓${NC} Cluster deleted"
            ((RESOURCES_DELETED++))
        fi
    done
    echo ""
}

# Delete S3 Buckets
delete_s3_buckets() {
    echo -e "${CYAN}Deleting S3 Buckets...${NC}"
    
    local buckets=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, '${PROJECT_NAME}')].Name" \
        --output text 2>/dev/null)
    
    for bucket in $buckets; do
        echo -e "  Emptying bucket: ${bucket}"
        aws s3 rm "s3://${bucket}" --recursive &> /dev/null || true
        
        echo -e "  Deleting bucket: ${bucket}"
        aws s3api delete-bucket --bucket "$bucket" --region "$REGION" &> /dev/null || true
        echo -e "  ${GREEN}✓${NC} Bucket deleted"
        ((RESOURCES_DELETED++))
    done
    echo ""
}

# Delete DynamoDB Tables
delete_dynamodb_tables() {
    echo -e "${CYAN}Deleting DynamoDB Tables...${NC}"
    
    local tables=$(aws dynamodb list-tables \
        --region "$REGION" \
        --query "TableNames[?contains(@, '${PROJECT_NAME}')]" \
        --output text 2>/dev/null)
    
    for table in $tables; do
        echo -e "  Deleting table: ${table}"
        aws dynamodb delete-table --region "$REGION" --table-name "$table" &> /dev/null
        echo -e "  ${GREEN}✓${NC} Table deleted"
        ((RESOURCES_DELETED++))
    done
    echo ""
}

# Delete CloudWatch Log Groups
delete_log_groups() {
    echo -e "${CYAN}Deleting CloudWatch Log Groups...${NC}"
    
    local log_groups=$(aws logs describe-log-groups \
        --region "$REGION" \
        --log-group-name-prefix "/ecs/${PROJECT_NAME}" \
        --query 'logGroups[*].logGroupName' \
        --output text 2>/dev/null)
    
    for log_group in $log_groups; do
        echo -e "  Deleting log group: ${log_group}"
        aws logs delete-log-group --region "$REGION" --log-group-name "$log_group" &> /dev/null
        echo -e "  ${GREEN}✓${NC} Log group deleted"
        ((RESOURCES_DELETED++))
    done
    echo ""
}

# Show menu
show_menu() {
    echo -e "${BOLD}${BLUE}What would you like to do?${NC}"
    echo ""
    echo -e "${CYAN}1)${NC} List all Phase 1 resources"
    echo -e "${CYAN}2)${NC} Stop EC2 instances (saves money, keeps resources)"
    echo -e "${CYAN}3)${NC} Delete all resources using Terraform (RECOMMENDED)"
    echo -e "${CYAN}4)${NC} Delete all resources manually (if Terraform fails)"
    echo -e "${CYAN}5)${NC} Delete specific resource types"
    echo -e "${CYAN}6)${NC} Exit"
    echo ""
}

# Delete specific resources
delete_specific() {
    echo ""
    echo -e "${BOLD}${BLUE}Select resources to delete:${NC}"
    echo ""
    echo -e "${CYAN}1)${NC} EC2 Instances"
    echo -e "${CYAN}2)${NC} NAT Gateways & Elastic IPs"
    echo -e "${CYAN}3)${NC} ECS Clusters"
    echo -e "${CYAN}4)${NC} S3 Buckets"
    echo -e "${CYAN}5)${NC} DynamoDB Tables"
    echo -e "${CYAN}6)${NC} CloudWatch Log Groups"
    echo -e "${CYAN}7)${NC} All of the above"
    echo -e "${CYAN}8)${NC} Back to main menu"
    echo ""
    read -p "Enter choice [1-8]: " choice
    
    case $choice in
        1)
            echo ""
            read -p "Terminate all EC2 instances? [y/N]: " confirm
            [ "$confirm" = "y" ] && manual_delete
            ;;
        2)
            echo ""
            read -p "Delete NAT Gateways and Elastic IPs? [y/N]: " confirm
            [ "$confirm" = "y" ] && manual_delete
            ;;
        3)
            echo ""
            read -p "Delete ECS Clusters? [y/N]: " confirm
            [ "$confirm" = "y" ] && delete_ecs_clusters
            ;;
        4)
            echo ""
            read -p "Delete S3 Buckets? [y/N]: " confirm
            [ "$confirm" = "y" ] && delete_s3_buckets
            ;;
        5)
            echo ""
            read -p "Delete DynamoDB Tables? [y/N]: " confirm
            [ "$confirm" = "y" ] && delete_dynamodb_tables
            ;;
        6)
            echo ""
            read -p "Delete CloudWatch Log Groups? [y/N]: " confirm
            [ "$confirm" = "y" ] && delete_log_groups
            ;;
        7)
            echo ""
            echo -e "${RED}${BOLD}WARNING: This will delete ALL resources!${NC}"
            read -p "Are you absolutely sure? Type 'DELETE' to confirm: " confirm
            if [ "$confirm" = "DELETE" ]; then
                delete_ecs_clusters
                delete_s3_buckets
                delete_dynamodb_tables
                delete_log_groups
                manual_delete
            fi
            ;;
        8)
            return
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
}

# Show summary
show_summary() {
    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}Teardown Summary${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Resources Found:${NC}    ${RESOURCES_FOUND}"
    echo -e "${CYAN}Resources Stopped:${NC}  ${RESOURCES_STOPPED}"
    echo -e "${CYAN}Resources Deleted:${NC}  ${RESOURCES_DELETED}"
    
    if [ $(echo "$COST_SAVINGS > 0" | bc -l) -eq 1 ]; then
        echo -e "${GREEN}${BOLD}Daily Cost Savings:${NC} ~\$${COST_SAVINGS}"
        local monthly_savings=$(echo "$COST_SAVINGS * 30" | bc)
        echo -e "${GREEN}${BOLD}Monthly Savings:${NC}    ~\$${monthly_savings}"
    fi
    
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Main function
main() {
    # Load environment
    load_env
    
    # Verify credentials
    verify_credentials
    
    # Main loop
    while true; do
        print_header
        show_menu
        read -p "Enter choice [1-6]: " choice
        
        case $choice in
            1)
                list_all_resources
                read -p "Press Enter to continue..."
                ;;
            2)
                echo ""
                list_all_resources
                echo -e "${YELLOW}${BOLD}Stop EC2 Instances${NC}"
                echo -e "${YELLOW}This will stop running instances but keep them available${NC}"
                echo ""
                read -p "Stop all running instances? [y/N]: " confirm
                if [ "$confirm" = "y" ]; then
                    stop_instances
                    show_summary
                fi
                read -p "Press Enter to continue..."
                ;;
            3)
                echo ""
                list_all_resources
                echo -e "${RED}${BOLD}WARNING: DESTRUCTIVE OPERATION!${NC}"
                echo -e "${RED}This will delete ALL Phase 1 infrastructure using Terraform${NC}"
                echo ""
                echo "Environment to destroy:"
                echo "  1) dev"
                echo "  2) staging"
                echo "  3) prod"
                echo ""
                read -p "Enter environment [1-3]: " env_choice
                
                case $env_choice in
                    1) env="dev" ;;
                    2) env="staging" ;;
                    3) env="prod" ;;
                    *) echo "Invalid choice"; continue ;;
                esac
                
                echo ""
                read -p "Type '${env}' to confirm deletion: " confirm
                if [ "$confirm" = "$env" ]; then
                    terraform_destroy "$env"
                    show_summary
                else
                    echo -e "${YELLOW}Deletion cancelled${NC}"
                fi
                read -p "Press Enter to continue..."
                ;;
            4)
                echo ""
                list_all_resources
                echo -e "${RED}${BOLD}WARNING: MANUAL DELETION!${NC}"
                echo -e "${RED}This will manually delete resources (use if Terraform fails)${NC}"
                echo ""
                read -p "Type 'DELETE' to confirm: " confirm
                if [ "$confirm" = "DELETE" ]; then
                    manual_delete
                    delete_ecs_clusters
                    delete_s3_buckets
                    delete_dynamodb_tables
                    delete_log_groups
                    show_summary
                else
                    echo -e "${YELLOW}Deletion cancelled${NC}"
                fi
                read -p "Press Enter to continue..."
                ;;
            5)
                delete_specific
                ;;
            6)
                echo ""
                echo -e "${GREEN}Exiting...${NC}"
                show_summary
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice${NC}"
                sleep 2
                ;;
        esac
    done
}

# Run main function
main
