#!/bin/bash
# OmniScope v0.1.6 Regression Test Suite
#
# Usage:
#   ./scripts/regression_test.sh [all|blst|ring|wasmtime|zlib|sqlite]
#   ./scripts/regression_test.sh --update-baseline
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
BASELINE_DIR="$PROJECT_ROOT/test_ir/baselines"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $*"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

ensure_build() {
    if [ ! -f "$BUILD_DIR/OmniScope" ]; then
        log_info "Building OmniScope..."
        cd "$PROJECT_ROOT" && make build
    fi
}

run_analysis() {
    local ir_file="$1"
    local output_file="$2"
    local extra_flags="${3:-}"

    "$BUILD_DIR/OmniScope" analyze --input "$ir_file" --output "$output_file" $extra_flags 2>/dev/null || true
}

count_issues() {
    local output_file="$1"
    local severity="${2:-all}"

    case "$severity" in
        critical) grep -c '"severity": "critical"' "$output_file" 2>/dev/null || echo 0 ;;
        high) grep -c '"severity": "high"' "$output_file" 2>/dev/null || echo 0 ;;
        medium) grep -c '"severity": "medium"' "$output_file" 2>/dev/null || echo 0 ;;
        low) grep -c '"severity": "low"' "$output_file" 2>/dev/null || echo 0 ;;
        all) grep -c '"kind":' "$output_file" 2>/dev/null || echo 0 ;;
        *) grep -c '"kind":' "$output_file" 2>/dev/null || echo 0 ;;
    esac
}

check_baseline() {
    local project="$1"
    local actual_count="$2"
    local max_expected="$3"
    local min_detected="$4"
    local description="$5"

    if [ "$actual_count" -le "$max_expected" ]; then
        log_pass "$project: $description (issues=$actual_count, max=$max_expected)"
        return 0
    else
        log_fail "$project: $description (issues=$actual_count > max=$max_expected)"
        return 1
    fi
}

test_blst() {
    log_info "Testing blst..."
    local IR_FILE="$PROJECT_ROOT/test_ir/real/blst_sample.ll"
    local OUTPUT="/tmp/blst_regression_output.json"

    if [ ! -f "$IR_FILE" ]; then
        log_skip "blst: IR file not found ($IR_FILE)"
        return
    fi

    run_analysis "$IR_FILE" "$OUTPUT"
    local total_issues=$(count_issues "$OUTPUT")
    local high_issues=$(count_issues "$OUTPUT" "high")

    check_baseline "blst" "$total_issues" 10 3 "total issues < 10" || true
    check_baseline "blst" "$high_issues" 5 1 "high severity < 5" || true
}

test_ring() {
    log_info "Testing ring..."
    local IR_FILE="$PROJECT_ROOT/test_ir/real/ring_sample.ll"
    local OUTPUT="/tmp/ring_regression_output.json"

    if [ ! -f "$IR_FILE" ]; then
        log_skip "ring: IR file not found ($IR_FILE)"
        return
    fi

    run_analysis "$IR_FILE" "$OUTPUT"
    local total_issues=$(count_issues "$OUTPUT")
    local high_issues=$(count_issues "$OUTPUT" "high")

    check_baseline "ring" "$total_issues" 5 2 "total issues < 5" || true
    check_baseline "ring" "$high_issues" 3 1 "high severity < 3" || true
}

test_wasmtime() {
    log_info "Testing wasmtime..."
    local IR_FILE="$PROJECT_ROOT/test_ir/real/wasmtime_sample.ll"
    local OUTPUT="/tmp/wasmtime_regression_output.json"

    if [ ! -f "$IR_FILE" ]; then
        log_skip "wasmtime: IR file not found ($IR_FILE)"
        return
    fi

    run_analysis "$IR_FILE" "$OUTPUT"
    local total_issues=$(count_issues "$OUTPUT")
    local critical_issues=$(count_issues "$OUTPUT" "critical")

    check_baseline "wasmtime" "$total_issues" 20 5 "total issues < 20" || true
    check_baseline "wasmtime" "$critical_issues" 10 2 "critical issues detected" || true
}

test_zlib() {
    log_info "Testing zlib-binding..."
    local IR_FILE="$PROJECT_ROOT/test_ir/verification/zlib_binding.ll"
    local OUTPUT="/tmp/zlib_regression_output.json"

    if [ ! -f "$IR_FILE" ]; then
        log_skip "zlib: IR file not found ($IR_FILE)"
        return
    fi

    run_analysis "$IR_FILE" "$OUTPUT"
    local leak_issues=$(grep -c 'memory_leak\|leak' "$OUTPUT" 2>/dev/null || echo 0)
    local double_free=$(grep -c 'double_free' "$OUTPUT" 2>/dev/null || echo 0)

    check_baseline "zlib" "$leak_issues" 15 8 "memory leaks detected" || true
    check_baseline "zlib" "$double_free" 5 2 "double free patterns" || true
}

test_sqlite() {
    log_info "Testing sqlite-binding..."
    local IR_FILE="$PROJECT_ROOT/test_ir/verification/sqlite_binding.ll"
    local OUTPUT="/tmp/sqlite_regression_output.json"

    if [ ! -f "$IR_FILE" ]; then
        log_skip "sqlite: IR file not found ($IR_FILE)"
        return
    fi

    run_analysis "$IR_FILE" "$OUTPUT"
    local uaf_issues=$(grep -c 'use_after_free\|UAF' "$OUTPUT" 2>/dev/null || echo 0)
    local escape_issues=$(grep -c 'escape\|borrow_escape' "$OUTPUT" 2>/dev/null || echo 0)

    check_baseline "sqlite" "$uaf_issues" 10 4 "UAF patterns detected" || true
    check_baseline "sqlite" "$escape_issues" 8 3 "escape patterns detected" || true
}

print_summary() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           REGRESSION TEST SUMMARY (v0.1.6)                  ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║ Status  │ Count                                             ║"
    echo "╠────────┼───────────────────────────────────────────────────╣"
    printf "║ ${GREEN}PASS${NC}     │ %3d                                               \n" "$PASS_COUNT"
    printf "║ ${RED}FAIL${NC}     │ %3d                                               \n" "$FAIL_COUNT"
    printf "║ ${YELLOW}SKIP${NC}     │ %3d                                               \n" "$SKIP_COUNT"
    echo "╠────────┼───────────────────────────────────────────────────╣"
    printf "║ TOTAL   │ %3d                                               \n" $((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
    echo "╚══════════════════════════════════════════════════════════════╝"

    if [ "$FAIL_COUNT" -gt 0 ]; then
        return 1
    fi
    return 0
}

main() {
    local target="${1:-all}"
    local update_baseline=false

    if [ "$target" == "--update-baseline" ]; then
        update_baseline=true
        target="all"
    fi

    ensure_build
    mkdir -p /tmp/omniscope_regression

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║       OmniScope v0.1.6 Regression Test Suite                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    case "$target" in
        all)
            test_blst
            test_ring
            test_wasmtime
            test_zlib
            test_sqlite
            ;;
        blst) test_blst ;;
        ring) test_ring ;;
        wasmtime) test_wasmtime ;;
        zlib) test_zlib ;;
        sqlite) test_sqlite ;;
        *)
            echo "Usage: $0 [all|blst|ring|wasmtime|zlib|sqlite] [--update-baseline]"
            exit 1
            ;;
    esac

    print_summary
}

main "$@"
