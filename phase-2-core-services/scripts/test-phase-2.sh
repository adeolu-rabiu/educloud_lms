#!/bin/bash

# ============================================
# Phase 2 - Application Testing Script
# ============================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "========================================"
echo "Phase 2 - Application Tests"
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

echo ""
echo "Running application tests..."
echo ""

# Test 1: Docker Compose services are running
run_test "Docker Services Running" "docker-compose ps | grep -q 'Up'"

# Test 2: PostgreSQL is accessible
run_test "PostgreSQL Health" "docker-compose exec -T postgres pg_isready -U educloud"

# Test 3: MongoDB is accessible
run_test "MongoDB Health" "docker-compose exec -T mongodb mongosh --eval 'db.adminCommand(\"ping\")' --quiet"

# Test 4: Redis is accessible
run_test "Redis Health" "docker-compose exec -T redis redis-cli ping | grep -q PONG"

# Test 5: Rails API is responding
run_test "Rails API Health" "curl -f -s http://localhost:3000/health > /dev/null 2>&1"

# Test 6: Node.js service is responding
run_test "Node Service Health" "curl -f -s http://localhost:8080/health > /dev/null 2>&1"

# Test 7: Rails database connection
run_test "Rails Database Connection" "docker-compose exec -T rails-api rails runner 'ActiveRecord::Base.connection.execute(\"SELECT 1\")' > /dev/null 2>&1"

# Test 8: Check Sidekiq is running
run_test "Sidekiq Running" "docker-compose ps sidekiq | grep -q 'Up'"

# Test 9: Check Redis connection from Rails
run_test "Rails Redis Connection" "docker-compose exec -T rails-api rails runner 'Redis.new.ping' > /dev/null 2>&1"

# Test 10: Check ports are listening
run_test "Ports Listening" "netstat -tuln 2>/dev/null | grep -E ':(3000|8080|5432|27017|6379)' || ss -tuln | grep -E ':(3000|8080|5432|27017|6379)'"

echo ""
echo "========================================"
echo "Container Status:"
echo "========================================"
docker-compose ps

echo ""
echo "========================================"
echo "Service Endpoints:"
echo "========================================"
echo "Rails API:     http://localhost:3000"
echo "Node Service:  http://localhost:8080"
echo "PostgreSQL:    localhost:5432"
echo "MongoDB:       localhost:27017"
echo "Redis:         localhost:6379"

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
    echo "Your Phase 2 applications are running correctly."
    echo ""
    echo "Next steps:"
    echo "1. Test endpoints manually:"
    echo "   curl http://localhost:3000/health"
    echo "   curl http://localhost:8080/health"
    echo "2. View application logs:"
    echo "   docker-compose logs -f rails-api"
    echo "   docker-compose logs -f node-service"
    echo "3. Commit your changes to Git"
    echo "4. Move to Phase 3: Caching & Queues"
    exit 0
else
    echo -e "${RED}✗ Some tests failed.${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check container logs:"
    echo "   docker-compose logs [service-name]"
    echo "2. Restart services:"
    echo "   docker-compose restart"
    echo "3. Rebuild if needed:"
    echo "   docker-compose down"
    echo "   docker-compose up --build -d"
    exit 1
fi
