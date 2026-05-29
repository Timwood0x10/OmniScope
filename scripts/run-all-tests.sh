#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="/tmp/omniscope-test-$(date +%Y%m%d_%H%M%S)"

mkdir -p "$LOG_DIR"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║         OmniScope Regression Test Suite                  ║"
echo "║         $(date '+%Y-%m-%d %H:%M:%S')                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0
TEST_RESULTS=()
DURATIONS=()

get_duration_ms() {
    local start=$1
    local end=$2
    if command -v python3 &>/dev/null; then
        python3 -c "print(int(($end - $start) * 1000))"
    elif command -v python &>/dev/null; then
        python -c "print int(($end - $start) * 1000)"
    else
        echo "0"
    fi
}

run_test_suite() {
    local name="$1"
    local command="$2"
    local optional="${3:-false}"
    
    echo "━━━ Running: $name ━━━"
    local start_time=$(date +%s.%N 2>/dev/null || date +%s)
    
    cd "$PROJECT_ROOT"
    
    if eval "$command" > "${LOG_DIR}/${name}.log" 2>&1; then
        local end_time=$(date +%s.%N 2>/dev/null || date +%s)
        local duration=$(get_duration_ms $start_time $end_time)
        echo "✅ PASSED (${duration}ms)"
        TEST_RESULTS+=("✅|${name}|${duration}ms")
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
        DURATIONS+=("$duration")
    else
        local end_time=$(date +%s.%N 2>/dev/null || date +%s)
        local duration=$(get_duration_ms $start_time $end_time)
        
        if [ "$optional" = "true" ]; then
            echo "⚠️  SKIPPED (optional, ${duration}ms)"
            TEST_RESULTS+=("⚠️|${name}|${duration}ms")
            TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
        else
            echo "❌ FAILED (${duration}ms)"
            TEST_RESULTS+=("❌|${name}|${duration}ms")
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
        fi
    fi
    echo ""
}

echo "========================================="
echo " Phase 1: Core Build & Unit Tests"
echo "========================================="
echo ""

run_test_suite "All Tests" "zig build test"

run_test_suite "Unit Tests" "zig build unit-test"

echo "========================================="
echo " Phase 2: Integration Tests"
echo "========================================="
echo ""

run_test_suite "Integration Tests" "zig build test-integration"

run_test_suite "Issue Verification" "zig build test-issues"

run_test_suite "Stability Tests" "zig build test-stability"

echo "========================================="
echo " Phase 3: Specialized Tests"
echo "========================================="
echo ""

run_test_suite "Semantic Resolution" "zig build test-semantic"

run_test_suite "E2E IR Tests" "zig build e2e-test" true

run_test_suite "Benchmark Tests" "zig build test-benchmark" true

echo "========================================="
echo " Phase 4: Code Quality"
echo "========================================="
echo ""

if zig fmt --check . > "${LOG_DIR}/formatting.log" 2>&1; then
    echo "✅ Formatting OK"
    TEST_RESULTS+=("✅|Code Formatting|0ms")
else
    echo "⚠️  Formatting issues found (run 'zig fmt .' to fix)"
    TEST_RESULTS+=("⚠️|Code Formatting|0ms")
    TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
fi
echo ""

if zig build check > "${LOG_DIR}/typecheck.log" 2>&1; then
    echo "✅ Type Check OK"
    TEST_RESULTS+=("✅|Type Check|0ms")
else
    echo "❌ Type Check Failed"
    TEST_RESULTS+=("❌|Type Check|0ms")
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi
echo ""

echo "========================================="
echo " Phase 5: Source-based Test Counting"
echo "========================================="
echo ""

count_tests() {
    local pattern="$1"
    local count
    count=$(find src tests -name "*.zig" -exec grep -l 'test "' {} \; 2>/dev/null | xargs grep -c 'test "' 2>/dev/null | awk -F: '{sum += $2} END {print sum+0}')
    echo "$count"
}

TOTAL_TEST_BLOCKS=$(count_tests 'test "')
echo "Total test blocks in source: ~$TOTAL_TEST_BLOCKS"
echo ""

echo "╔══════════════════════════════════════════════════════════╗"
echo "║                      SUMMARY                            ║"
echo "╠══════════════════════════════════════════════════════════╣"
printf "║  %-35s │ %8s │ %8s ║\n" "Test Suite" "Status" "Duration"
echo "╟──────────────────────────────────────┼──────────┼──────────╢"
for result in "${TEST_RESULTS[@]}"; do
    IFS='|' read -r status name duration <<< "$result"
    printf "║  %-35s │ %8s │ %8s ║\n" "$name" "$status" "$duration"
done
echo "╠══════════════════════════════════════════════════════════╣"
printf "║  Total: %d passed, %d failed, %d skipped   ║\n" "$TOTAL_PASSED" "$TOTAL_FAILED" "$TOTAL_SKIPPED"
echo "╚══════════════════════════════════════════════════════════╝"

echo ""
echo "📁 Log directory: $LOG_DIR"

if [ $TOTAL_FAILED -gt 0 ]; then
    echo ""
    echo "⚠️  Failed test logs:"
    for result in "${TEST_RESULTS[@]}"; do
        IFS='|' read -r status name duration <<< "$result"
        if [ "$status" = "❌" ]; then
            echo "  - ${LOG_DIR}/${name}.log"
        fi
    done
    exit 1
fi

exit 0
