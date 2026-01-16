#!/bin/bash
# K6 Performance Tests Runner for CI/CD
# Runs k6 tests in Docker with environment-based configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
TEST_ENV=${TEST_ENV:-test}
MAX_VUS=${MAX_VUS:-50}
TEST_TYPE=${TEST_TYPE:-full}
TEST_DURATION=${TEST_DURATION:-5}
TIMESTAMP=${TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}
RESULTS_DIR="results/${TEST_TYPE}-${TEST_ENV}-${TIMESTAMP}"
K6_IMAGE="grafana/k6:latest"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}K6 Performance Tests${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "Environment:  ${YELLOW}${TEST_ENV}${NC}"
echo -e "Max VUs:      ${YELLOW}${MAX_VUS}${NC}"
echo -e "Test Type:    ${YELLOW}${TEST_TYPE}${NC}"
echo -e "Duration:     ${YELLOW}${TEST_DURATION}m${NC}"
echo -e "Results:      ${YELLOW}${RESULTS_DIR}${NC}"
echo -e "${CYAN}========================================${NC}\n"

# Create results directory
mkdir -p "${RESULTS_DIR}"

# Function to run k6 test
run_k6_test() {
    local test_file=$1
    local test_name=$2
    local vus=$3
    local duration=$4
    local output_file="${RESULTS_DIR}/${test_name}.json"
    
    echo -e "${YELLOW}Running: ${test_name}${NC}"
    echo -e "Test file: ${test_file}"
    echo -e "VUs: ${vus}, Duration: ${duration}\n"
    
    docker run --rm \
        --network host \
        -v "$(pwd)/k6:/k6" \
        -v "$(pwd)/results:/results" \
        -e K6_ENV="${TEST_ENV}" \
        -e K6_MAX_VUS="${MAX_VUS}" \
        ${K6_IMAGE} run \
        --insecure-skip-tls-verify \
        --out "json=/results/${test_name}.json" \
        --vus "${vus}" \
        --duration "${duration}" \
        "/k6/dist/${test_file}" || return 1
    
    echo -e "${GREEN}✓ ${test_name} completed${NC}\n"
    return 0
}

# Calculate scaled VUs based on max
calc_vus() {
    local base=$1
    local max=$2
    echo $(( base > max ? max : base ))
}

# Run tests based on type
case "${TEST_TYPE}" in
    smoke)
        echo -e "${CYAN}=== SMOKE TEST ===${NC}\n"
        run_k6_test "instant-servers.test.js" "smoke-test" 1 "30s"
        ;;
        
    baseline)
        echo -e "${CYAN}=== BASELINE TEST ===${NC}\n"
        BASELINE_VUS=$(calc_vus 10 ${MAX_VUS})
        run_k6_test "e2e-simple.test.js" "baseline-test" ${BASELINE_VUS} "${TEST_DURATION}"
        ;;
        
    load)
        echo -e "${CYAN}=== LOAD TEST ===${NC}\n"
        LOAD_VUS=$(calc_vus 50 ${MAX_VUS})
        run_k6_test "e2e-simple.test.js" "load-test" ${LOAD_VUS} "${TEST_DURATION}"
        ;;
        
    stress)
        echo -e "${CYAN}=== STRESS TEST ===${NC}\n"
        STRESS_VUS=${MAX_VUS}
        run_k6_test "e2e-simple.test.js" "stress-test" ${STRESS_VUS} "${TEST_DURATION}"
        ;;
        
    full)
        echo -e "${CYAN}=== FULL TEST SUITE ===${NC}\n"
        
        # Phase 1: Smoke Test
        echo -e "${CYAN}Phase 1: Smoke Test${NC}"
        run_k6_test "instant-servers.test.js" "phase1-smoke" 1 "30s" || exit 1
        sleep 10
        
        # Phase 2: Single E2E
        echo -e "${CYAN}Phase 2: Single E2E${NC}"
        run_k6_test "e2e-simple.test.js" "phase2-single-e2e" 1 "1m" || exit 1
        sleep 10
        
        # Phase 3: Baseline
        echo -e "${CYAN}Phase 3: Baseline${NC}"
        BASELINE_VUS=$(calc_vus 10 ${MAX_VUS})
        run_k6_test "e2e-simple.test.js" "phase3-baseline" ${BASELINE_VUS} "5m" || exit 1
        sleep 30
        
        # Phase 4: Load Test
        if [ ${MAX_VUS} -ge 25 ]; then
            echo -e "${CYAN}Phase 4: Load Test${NC}"
            LOAD_VUS=$(calc_vus 50 ${MAX_VUS})
            run_k6_test "e2e-simple.test.js" "phase4-load" ${LOAD_VUS} "10m" || exit 1
            sleep 30
        fi
        
        # Phase 5: Stress Test
        if [ ${MAX_VUS} -ge 50 ]; then
            echo -e "${CYAN}Phase 5: Stress Test${NC}"
            run_k6_test "e2e-simple.test.js" "phase5-stress" ${MAX_VUS} "15m" || exit 1
        fi
        ;;
        
    *)
        echo -e "${RED}Unknown test type: ${TEST_TYPE}${NC}"
        echo "Valid types: smoke, baseline, load, stress, full"
        exit 1
        ;;
esac

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Tests Completed Successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Results saved to: ${YELLOW}${RESULTS_DIR}${NC}\n"

# List generated files
echo -e "Generated files:"
ls -lh "${RESULTS_DIR}"

exit 0
