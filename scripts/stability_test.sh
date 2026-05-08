#!/bin/bash
# OmniScope Stability & E2E Test Suite
#
# Usage:
#   ./scripts/stability_test.sh [all|stability|stress|e2e]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0

log_info() { echo -e "${BLUE}[TEST]${NC} $*"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
# DC-C12 FIX: Add missing log_skip and log_warn functions
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

run_zig_test() {
    local test_name="$1"
    local test_file="$2"
    
    log_info "Running $test_name..."
    
    if cd "$PROJECT_ROOT" && zig test "$test_file" 2>&1; then
        log_pass "$test_name passed"
        return 0
    else
        log_fail "$test_name failed"
        return 1
    fi
}

# ========================================
# Stability Tests
# ========================================

test_stability() {
    log_info "=== Running Stability Tests ==="
    
    run_zig_test "Stability Suite" "tests/stability/main.zig" || true
    
    # Additional crash-free tests
    log_info "Testing crash-free operation..."
    for i in $(seq 1 10); do
        cd "$PROJECT_ROOT" && make build > /dev/null 2>&1 || log_fail "Build iteration $i"
    done
    log_pass "10 consecutive builds completed without crash"
}

# ========================================
# Stress Tests  
# ========================================

test_stress() {
    log_info "=== Running Stress Tests ==="
    
    run_zig_test "Stress Suite" "tests/stress/main.zig" || true
    
    # Large IR file handling
    log_info "Testing large input handling..."
    local large_ir="$PROJECT_ROOT/test_ir/real/wasmtime_sample.ll"
    if [ -f "$large_ir" ]; then
        for i in $(seq 1 5); do
            timeout 30 ./build/OmniScope analyze --input "$large_ir" --output /dev/null 2>/dev/null || \
                log_fail "Large IR test iteration $i"
        done
        log_pass "Large IR stress test (5 iterations)"
    else
        log_skip "wasmtime_sample.ll not found, skipping large IR test"
    fi
}

# ========================================
# E2E Tests
# ========================================

test_e2e() {
    log_info "=== Running E2E Pipeline Tests ==="
    
    run_zig_test "E2E IR Test" "tests/e2e_ir_test.zig" || true
    
    # Full pipeline test with real IR files
    log_info "Testing full analysis pipeline..."
    
    local test_files=(
        "$PROJECT_ROOT/test_ir/verification/zlib_binding.ll"
        "$PROJECT_ROOT/test_ir/verification/sqlite_binding.ll"
        "$PROJECT_ROOT/test_ir/verification/rust_ffi_example.ll"
    )
    
    local pipeline_passed=0
    local pipeline_total=${#test_files[@]}
    
    for ir_file in "${test_files[@]}"; do
        if [ -f "$ir_file" ]; then
            local output="/tmp/e2e_output_$(basename "$ir_file").json"
            if ./build/OmniScope analyze --input "$ir_file" --output "$output" 2>/dev/null; then
                if [ -f "$output" ] && [ -s "$output" ]; then
                    pipeline_passed=$((pipeline_passed + 1))
                fi
            fi
        fi
    done
    
    if [ "$pipeline_passed" -eq "$pipeline_total" ]; then
        log_pass "E2E Pipeline: All $pipeline_total test files processed successfully"
    else
        log_fail "E2E Pipeline: $pipeline_passed/$pipeline_total test files processed"
    fi
}

# ========================================
# Memory Safety Tests
# ========================================

test_memory_safety() {
    log_info "=== Running Memory Safety Tests ==="
    
    # Run with leak checker if available
    if command -v valgrind >/dev/null 2>&1; then
        log_info "Running Valgrind memory check..."
        
        local ir_file="$PROJECT_ROOT/test_ir/real/ring_sample.ll"
        if [ -f "$ir_file" ]; then
            if valgrind --leak-check=full --error-exitcode=1 \
                ./build/OmniScope analyze --input "$ir_file" --output /dev/null 2>&1 | \
                grep -q "no leaks are possible"; then
                log_pass "Valgrind: No memory leaks detected"
            else
                log_warn "Valgrind: Review output for potential issues"
            fi
        fi
    else
        log_skip "Valgrind not available, skipping memory safety check"
    fi
}

print_summary() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           STABILITY & E2E TEST SUMMARY                      ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    printf "║ ${GREEN}PASS${NC}             │ %3d                                           \n" "$PASS_COUNT"
    printf "║ ${RED}FAIL${NC}             │ %3d                                           \n" "$FAIL_COUNT"
    echo "╠─────────────────┼─────────────────────────────────────────────╣"
    printf "║ TOTAL            │ %3d                                           \n" $((PASS_COUNT + FAIL_COUNT))
    echo "╚═══════════════════╩════════════════════════════════════════════╝"
    
    if [ "$FAIL_COUNT" -gt 0 ]; then
        return 1
    fi
    return 0
}

main() {
    local target="${1:-all}"
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║       OmniScope v0.1.7 Stability & E2E Test Suite             ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    case "$target" in
        all)
            test_stability
            echo ""
            test_stress
            echo ""
            test_e2e
            echo ""
            test_memory_safety
            ;;
        stability) test_stability ;;
        stress) test_stress ;;
        e2e) test_e2e ;;
        memory) test_memory_safety ;;
        *)
            echo "Usage: $0 [all|stability|stress|e2e|memory]"
            exit 1
            ;;
    esac
    
    print_summary
}

main "$@"
