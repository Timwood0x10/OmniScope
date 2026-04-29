#!/bin/bash
# OmniScope v0.1.8 Regression Test Suite
#
# Usage:
#   ./scripts/regression_test.sh [all|small|medium|large|ffi-dense]
#   make regression-test   # via Makefile
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/zig-out/bin"
OMNISCOPE="$BUILD_DIR/omniscope"

CORPUS_SMALL="$PROJECT_ROOT/corpus/small"
CORPUS_MEDIUM="$PROJECT_ROOT/corpus/medium"
CORPUS_LARGE="$PROJECT_ROOT/corpus/large"
CORPUS_FFI="$PROJECT_ROOT/corpus/ffi-dense"
CORPUS_RED="$PROJECT_ROOT/corpus/red_team_test"

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

test_file() {
    local name="$1"
    local ir_file="$2"
    local expected_min="${3:-0}"
    local expected_max="${4:-999999}"
    local format="${5:-"--json"}"

    local tmp_output="/tmp/omniscope_regression_${name}.$$.out"
    local display_name="$name"

    printf "  %-30s " "$display_name"

    if [ ! -f "$ir_file" ]; then
        echo -e "${YELLOW}[SKIP]${NC}  (IR not found)"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        return
    fi

    run_analysis "$ir_file" "$tmp_output" "$format"
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

compile_corpus_file() {
    local src_file="$1"
    local out_file="$2"
    local lang="${3:-c}"

    if [ ! -f "$src_file" ]; then
        return 1
    fi

    case "$lang" in
        c)
            clang -S -emit-llvm -O0 -g -I"$PROJECT_ROOT/corpus" -o "$out_file" "$src_file" 2>/dev/null || true
            ;;
        rust)
            if command -v rustc &>/dev/null; then
                rustc --emit=llvm-ir -O -o "$out_file" "$src_file" 2>/dev/null || true
            fi
            ;;
        go)
            if command -v go &>/dev/null; then
                go tool compile -S "$src_file" 2>/dev/null | llvm-as -o "$out_file" 2>/dev/null || true
            fi
            ;;
        cpp)
            clang++ -S -emit-llvm -O0 -g -std=c++17 -I"$PROJECT_ROOT/corpus" -o "$out_file" "$src_file" 2>/dev/null || true
            ;;
        zig)
            zig build-obj -O ReleaseFast --emit-llvm-ir -fno-emit-bin -femit-asm="$out_file" "$src_file" 2>/dev/null || true
            ;;
    esac
}

test_small() {
    echo ""
    echo "=== small/ FFI Test Cases ==="
    mkdir -p /tmp/omniscope_regression

    local rust_ll="./test_ir/rust_ffi_simple.ll"
    local zig_ll="./test_ir/zig_ffi_simple.ll"
    local go_ll="./test_ir/go_ffi_simple.ll"
    local cpp_ll="./test_ir/cpp_ffi_simple.ll"

    compile_corpus_file "$CORPUS_SMALL/rust_ffi_simple.rs" "$rust_ll" rust
    compile_corpus_file "$CORPUS_SMALL/zig_ffi_simple.zig" "$zig_ll" zig
    compile_corpus_file "$CORPUS_SMALL/go_ffi_simple.go" "$go_ll" go
    compile_corpus_file "$CORPUS_SMALL/cpp_ffi_simple.cpp" "$cpp_ll" cpp

    test_file "rust_ffi_simple" "$rust_ll" 1 10
    test_file "zig_ffi_simple" "$zig_ll" 1 10
    test_file "go_ffi_simple" "$go_ll" 1 10
    test_file "cpp_ffi_simple" "$cpp_ll" 1 10
}

test_medium() {
    echo ""
    echo "=== medium/ FFI Test Cases ==="

    local boundary_ll="/tmp/omniscope_regression/boundary_test.ll"
    compile_corpus_file "$CORPUS_MEDIUM/boundary_test.c" "$boundary_ll" c

    test_file "boundary_test" "$boundary_ll" 5 30
}

test_large() {
    echo ""
    echo "=== large/ FFI Test Cases ==="

    local stress_ll="/tmp/omniscope_regression/stress_patterns.ll"
    compile_corpus_file "$CORPUS_LARGE/stress_patterns.c" "$stress_ll" c

    test_file "stress_patterns" "$stress_ll" 10 100
}

test_ffi_dense() {
    echo ""
    echo "=== ffi-dense/ FFI Test Cases ==="

    local sqlite_ll="/tmp/omniscope_regression/sqlite_binding.ll"
    local openssl_ll="/tmp/omniscope_regression/openssl_wrapper.ll"
    local zlib_ll="/tmp/omniscope_regression/zlib_binding.ll"
    local rust_sql_ll="/tmp/omniscope_regression/rust_sqlite_ffi.ll"

    compile_corpus_file "$CORPUS_FFI/sqlite_binding.c" "$sqlite_ll" c
    compile_corpus_file "$CORPUS_FFI/openssl_wrapper.c" "$openssl_ll" c
    compile_corpus_file "$CORPUS_FFI/zlib_binding.c" "$zlib_ll" c
    compile_corpus_file "$CORPUS_FFI/rust_sqlite_ffi.rs" "$rust_sql_ll" rust

    test_file "sqlite_binding" "$sqlite_ll" 1 10
    test_file "openssl_wrapper" "$openssl_ll" 1 15
    test_file "zlib_binding" "$zlib_ll" 1 15
    test_file "rust_sqlite_ffi" "$rust_sql_ll" 1 10
}

test_red_team() {
    echo ""
    echo "=== red_team_test/ FFI Test Cases ==="

    local posix_ll="/tmp/omniscope_regression/posix_ffi_bugs.ll"
    local ffi_ll="/tmp/omniscope_regression/ffi_boundary_bugs.ll"
    local red_ll="/tmp/omniscope_regression/red_team_bugs.ll"

    compile_corpus_file "$CORPUS_RED/posix_ffi_bugs.c" "$posix_ll" c
    compile_corpus_file "$CORPUS_RED/ffi_boundary_bugs.c" "$ffi_ll" c
    compile_corpus_file "$CORPUS_RED/red_team_bugs.c" "$red_ll" c

    test_file "posix_ffi_bugs" "$posix_ll" 1 15
    test_file "ffi_boundary_bugs" "$ffi_ll" 1 20
    test_file "red_team_bugs" "$red_ll" 1 20
}

test_sarif_output() {
    echo ""
    echo "=== SARIF Output Format Test ==="

    local test_ll="/tmp/omniscope_regression/sarif_test.ll"
    local sarif_out="/tmp/omniscope_regression/sarif_output.sarif"

    compile_corpus_file "$CORPUS_RED/posix_ffi_bugs.c" "$test_ll" c

    printf "  %-30s " "sarif_format"

    if [ ! -f "$test_ll" ]; then
        echo -e "${YELLOW}[SKIP]${NC}  (IR not found)"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        return
    fi

    "$OMNISCOPE" "$test_ll" --sarif -o "$sarif_out" 2>/dev/null || true

    if [ ! -f "$sarif_out" ]; then
        echo -e "${RED}[FAIL]${NC}  (no output file)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
    fi

    # Check that it's valid JSON and contains SARIF structure
    if python3 -c "import json; d=json.load(open('$sarif_out')); assert 'version' in d; assert 'runs' in d; assert len(d['runs']) > 0" 2>/dev/null; then
        echo -e "${GREEN}[PASS]${NC}  (valid SARIF JSON)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}[FAIL]${NC}  (invalid SARIF JSON)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    rm -f "$sarif_out" "$test_ll"
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

    mkdir -p /tmp/omniscope_regression

    case "$target" in
        all)
            test_small
            test_medium
            test_large
            test_ffi_dense
            test_red_team
            test_sarif_output
            ;;
        small)     test_small ;;
        medium)    test_medium ;;
        large)     test_large ;;
        ffi-dense) test_ffi_dense ;;
        red-team)  test_red_team ;;
        sarif)     test_sarif_output ;;
        *)
            echo "Usage: $0 [all|small|medium|large|ffi-dense|red-team|sarif]"
            exit 1
            ;;
    esac

    print_summary
}

main "$@"
