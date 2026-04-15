#!/bin/bash
# OmniScope Example Runner Script
# Usage: ./run_examples.sh [example_name]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EXAMPLES_DIR="$PROJECT_ROOT/examples"
ZIG_OUT="$PROJECT_ROOT/zig-out/bin/OmniScope"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

echo_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if OmniScope is built
if [ ! -f "$ZIG_OUT" ]; then
    echo_error "OmniScope not found at $ZIG_OUT"
    echo_info "Building OmniScope..."
    cd "$PROJECT_ROOT"
    zig build
    echo_step "Build complete"
fi

# List available examples
list_examples() {
    echo "Available examples:"
    echo "  1. cffi_test     - Cross-language FFI test (C)"
    echo "  2. logic_bugs    - Logic bug patterns (C)"
    echo "  3. sample_rust   - Rust patterns (requires Rust)"
    echo "  4. sample_zig   - Zig patterns (requires Zig)"
    echo "  5. all           - Run all examples"
    echo ""
    echo "Usage: $0 [example_name]"
}

# Compile C example to LLVM IR
compile_c_example() {
    local src_file=$1
    local bc_file="${src_file%.c}.bc"

    if [ ! -f "$bc_file" ]; then
        echo_step "Compiling $src_file to LLVM IR..."
        clang -c -emit-llvm -O0 -g "$src_file" -o "$bc_file"
        echo_info "Generated: $bc_file"
    else
        echo_info "Using existing: $bc_file"
    fi
}

# Run analysis on an IR file
run_analysis() {
    local ir_file=$1
    local name=$2

    echo_step "Running analysis: $name"
    echo "---"
    "$ZIG_OUT" "$ir_file" || true
    echo "---"
    echo ""
}

# Example 1: cffi_test
run_cffi_test() {
    echo_step "=== C FFI Test ==="
    cd "$EXAMPLES_DIR"
    compile_c_example "cffi_test.c"
    run_analysis "cffi_test.bc" "cffi_test"
}

# Example 2: logic_bugs
run_logic_bugs() {
    echo_step "=== Logic Bugs Test ==="
    cd "$EXAMPLES_DIR"
    compile_c_example "logic_bugs.c"
    run_analysis "logic_bugs.bc" "logic_bugs"
}

# Example 3: sample_rust (if rustc available)
run_sample_rust() {
    if ! command -v rustc &> /dev/null; then
        echo_info "Skipping sample_rust (rustc not found)"
        return
    fi

    echo_step "=== Rust Sample Test ==="
    cd "$EXAMPLES_DIR"

    if [ ! -f "sample_rust.bc" ]; then
        echo_info "Compiling sample_rust.rs..."
        rustc --crate-type=lib --emit=llvm-bc sample_rust.rs -o sample_rust.bc 2>/dev/null || {
            echo_info "Rust compilation failed, skipping"
            return
        }
    fi

    run_analysis "sample_rust.bc" "sample_rust"
}

# Example 4: sample_zig (if zig available)
run_sample_zig() {
    if ! command -v zig &> /dev/null; then
        echo_info "Skipping sample_zig (zig not found)"
        return
    fi

    echo_step "=== Zig Sample Test ==="
    cd "$EXAMPLES_DIR"

    if [ ! -f "sample_zig.bc" ]; then
        echo_info "Compiling sample_zig.zig..."
        zig build-obj sample_zig.zig -femit-llvm=sample_zig.bc 2>/dev/null || {
            echo_info "Zig compilation failed, skipping"
            return
        }
    fi

    run_analysis "sample_zig.bc" "sample_zig"
}

# Run all examples
run_all() {
    run_cffi_test
    run_logic_bugs
    run_sample_rust
    run_sample_zig
    echo_step "=== All examples complete ==="
}

# Main
main() {
    echo "OmniScope Example Runner"
    echo "======================="
    echo ""

    case "${1:-}" in
        "" | "all")
            run_all
            ;;
        "cffi_test")
            run_cffi_test
            ;;
        "logic_bugs")
            run_logic_bugs
            ;;
        "sample_rust")
            run_sample_rust
            ;;
        "sample_zig")
            run_sample_zig
            ;;
        "list"|"-l"|"--list")
            list_examples
            ;;
        *)
            echo_error "Unknown example: $1"
            list_examples
            exit 1
            ;;
    esac
}

main "$@"
