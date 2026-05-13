#!/bin/bash
# OmniScope v0.1.8 Regression Test Suite
#
# Usage:
#   ./scripts/regression_test.sh [all|c|cpp|rust|go|zig|sarif|json]
#   make regression-test   # via Makefile
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/zig-out/bin"
# DC-C11 FIX: Use correct binary name (capital O as defined in build.zig)
OMNISCOPE="$BUILD_DIR/OmniScope"

TEST_IR_DIR="$PROJECT_ROOT/tests/ir"
BC_DIR="$TEST_IR_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TOTAL_ISSUES=0

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_pass()  { echo -e "${GREEN}[PASS]${NC}  $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
log_fail()  { echo -e "${RED}[FAIL]${NC}  $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
log_skip()  { echo -e "${YELLOW}[SKIP]${NC}  $*"; SKIP_COUNT=$((SKIP_COUNT + 1)); }
log_issue() { echo -e "       ${CYAN}[ISSUE]${NC}  $*"; }

ensure_build() {
    if [ ! -f "$OMNISCOPE" ]; then
        log_info "Building OmniScope..."
        cd "$PROJECT_ROOT" && zig build
    fi
}

compile_to_bc() {
    local src_file="$1"
    local out_file="$2"
    local lang="$3"

    if [ ! -f "$src_file" ]; then
        return 1
    fi

    case "$lang" in
        c)
            clang -c -emit-llvm -O0 -g -o "$out_file" "$src_file" 2>/dev/null
            ;;
        cpp)
            clang++ -c -emit-llvm -O0 -g -std=c++17 -o "$out_file" "$src_file" 2>/dev/null
            ;;
        rust)
            if command -v rustc &>/dev/null; then
                rustc --emit=llvm-bc -O -o "$out_file" "$src_file" 2>/dev/null || true
            fi
            ;;
        go)
            if command -v go &>/dev/null && command -v llvm-as &>/dev/null; then
                go tool compile -S "$src_file" 2>/dev/null | llvm-as -o "$out_file" 2>/dev/null || true
            fi
            ;;
        zig)
            if command -v zig &>/dev/null; then
                local zig_dir
                zig_dir=$(dirname "$src_file")
                rm -f "$out_file"
                (cd "$zig_dir" && zig build-obj -O ReleaseFast -femit-llvm-bc -fno-emit-bin "$(basename "$src_file")" 2>/dev/null) || true
            fi
            ;;
    esac
}

run_analysis() {
    local ir_file="$1"
    local output_file="$2"
    local format="${3:-"--json"}"

    if [ ! -f "$ir_file" ]; then
        echo "SKIP: $ir_file not found"
        return 1
    fi

    "$OMNISCOPE" "$ir_file" $format -o "$output_file" 2>/dev/null || true

    if [ ! -f "$output_file" ] || [ ! -s "$output_file" ]; then
        return 1
    fi
    return 0
}

count_issues_json() {
    local output_file="$1"
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print(len(d.get('issues', [])))
except:
    print(0)
" "$output_file" 2>/dev/null || echo 0
}

count_issues_sarif() {
    local output_file="$1"
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    runs = d.get('runs', [])
    print(len(runs[0].get('results', [])) if runs else 0)
except:
    print(0)
" "$output_file" 2>/dev/null || echo 0
}

test_ir_file() {
    local name="$1"
    local bc_file="$BC_DIR/${name}.bc"
    local expected_min="${2:-0}"
    local expected_max="${3:-999999}"
    local format="${4:-"--json"}"

    local tmp_output="/tmp/omniscope_regression_${name}.$$.out"

    printf "  %-30s " "$name"

    if [ ! -f "$bc_file" ]; then
        echo -e "${YELLOW}[SKIP]${NC}  (IR not found)"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        return
    fi

    run_analysis "$bc_file" "$tmp_output" "$format"
    local issues=0
    if [ "$format" = "--sarif" ]; then
        issues=$(count_issues_sarif "$tmp_output")
    else
        issues=$(count_issues_json "$tmp_output")
    fi

    rm -f "$tmp_output"

    if [ "$issues" -ge "$expected_min" ] && [ "$issues" -le "$expected_max" ]; then
        echo -e "${GREEN}[PASS]${NC}  issues=$issues (expected $expected_min-$expected_max)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}[FAIL]${NC}  issues=$issues (expected $expected_min-$expected_max)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    TOTAL_ISSUES=$((TOTAL_ISSUES + issues))
}

compile_all_ir() {
    log_info "Compiling test IR files to $BC_DIR..."

    compile_to_bc "$TEST_IR_DIR/test_c_control_flow.c" "$BC_DIR/test_c_control_flow.bc" c
    compile_to_bc "$TEST_IR_DIR/test_c_pointers.c" "$BC_DIR/test_c_pointers.bc" c
    compile_to_bc "$TEST_IR_DIR/test_c_threads.c" "$BC_DIR/test_c_threads.bc" c
    compile_to_bc "$TEST_IR_DIR/test_cpp_classes.cpp" "$BC_DIR/test_cpp_classes.bc" cpp
    compile_to_bc "$TEST_IR_DIR/test_cpp_virtual.cpp" "$BC_DIR/test_cpp_virtual.bc" cpp
    compile_to_bc "$TEST_IR_DIR/test_rust_patterns.rs" "$BC_DIR/test_rust_patterns.bc" rust
    compile_to_bc "$TEST_IR_DIR/test_go_noise.c" "$BC_DIR/test_go_noise.bc" go
    compile_to_bc "$TEST_IR_DIR/test_zig_comptime.zig" "$BC_DIR/test_zig_comptime.bc" zig

    log_info "IR compilation complete"
}

test_c() {
    echo ""
    echo "=== C Test Cases ==="

    test_ir_file "test_c_control_flow" 0 10
    test_ir_file "test_c_pointers" 0 10
    test_ir_file "test_c_threads" 0 10
}

test_cpp() {
    echo ""
    echo "=== C++ Test Cases ==="

    test_ir_file "test_cpp_classes" 0 20
    test_ir_file "test_cpp_virtual" 0 20
}

test_rust() {
    echo ""
    echo "=== Rust Test Cases ==="

    test_ir_file "test_rust_patterns" 0 10
}

test_go() {
    echo ""
    echo "=== Go Test Cases ==="

    test_ir_file "test_go_noise" 0 10
}

test_zig() {
    echo ""
    echo "=== Zig Test Cases ==="

    test_ir_file "test_zig_comptime" 0 30
}

test_sarif_output() {
    echo ""
    echo "=== SARIF Output Format Test ==="

    local sarif_out="/tmp/omniscope_regression_sarif.out"

    printf "  %-30s " "sarif_format"

    if [ ! -f "$BC_DIR/test_c_control_flow.bc" ]; then
        echo -e "${YELLOW}[SKIP]${NC}  (IR not found)"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        return
    fi

    "$OMNISCOPE" "$BC_DIR/test_c_control_flow.bc" --sarif -o "$sarif_out" 2>/dev/null || true

    if [ ! -f "$sarif_out" ]; then
        echo -e "${RED}[FAIL]${NC}  (no output file)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
    fi

    if python3 -c "import json; d=json.load(open('$sarif_out')); assert 'version' in d; assert 'runs' in d; assert len(d['runs']) > 0" 2>/dev/null; then
        echo -e "${GREEN}[PASS]${NC}  (valid SARIF JSON)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}[FAIL]${NC}  (invalid SARIF JSON)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    rm -f "$sarif_out"
}

test_json_output() {
    echo ""
    echo "=== JSON Output Format Test ==="

    local json_out="/tmp/omniscope_regression_json.out"

    printf "  %-30s " "json_format"

    if [ ! -f "$BC_DIR/test_c_control_flow.bc" ]; then
        echo -e "${YELLOW}[SKIP]${NC}  (IR not found)"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        return
    fi

    "$OMNISCOPE" "$BC_DIR/test_c_control_flow.bc" --json -o "$json_out" 2>/dev/null || true

    if [ ! -f "$json_out" ]; then
        echo -e "${RED}[FAIL]${NC}  (no output file)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
    fi

    if python3 -c "import json; d=json.load(open('$json_out')); assert 'issues' in d" 2>/dev/null; then
        echo -e "${GREEN}[PASS]${NC}  (valid JSON)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}[FAIL]${NC}  (invalid JSON)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    rm -f "$json_out"
}

print_summary() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           OmniScope v0.1.8 Regression Test Summary           ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  Status  │  Count                                             ║"
    echo "╠──────────┼──────────────────────────────────────────────────╣"
    printf "║  ${GREEN}PASS${NC}     │  %3d                                               \n" "$PASS_COUNT"
    printf "║  ${RED}FAIL${NC}     │  %3d                                               \n" "$FAIL_COUNT"
    printf "║  ${YELLOW}SKIP${NC}     │  %3d                                               \n" "$SKIP_COUNT"
    echo "╠──────────┼──────────────────────────────────────────────────╣"
    printf "║  TOTAL   │  %3d                                               \n" $((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
    printf "║  Issues  │  %3d                                               \n" "$TOTAL_ISSUES"
    echo "╚══════════════════════════════════════════════════════════════╝"

    if [ "$FAIL_COUNT" -gt 0 ]; then
        return 1
    fi
    return 0
}

main() {
    local target="${1:-all}"

    ensure_build

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║       OmniScope v0.1.8 Regression Test Suite                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"

    compile_all_ir

    case "$target" in
        all)
            test_c
            test_cpp
            test_rust
            test_go
            test_zig
            test_sarif_output
            test_json_output
            ;;
        c)          test_c ;;
        cpp)        test_cpp ;;
        rust)       test_rust ;;
        go)         test_go ;;
        zig)        test_zig ;;
        sarif)      test_sarif_output ;;
        json)       test_json_output ;;
        compile)    compile_all_ir ;;
        *)
            echo "Usage: $0 [all|c|cpp|rust|go|zig|sarif|json|compile]"
            exit 1
            ;;
    esac

    print_summary
}

main "$@"