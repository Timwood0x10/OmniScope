#!/bin/bash
# OmniScope Example Runner Script
# Usage: ./run_examples.sh [demo_name|test_name]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EXAMPLES_DIR="$PROJECT_ROOT/examples"
ZIG_OUT="$PROJECT_ROOT/zig-out/bin/OmniScope"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

echo_header() {
    echo -e "${BLUE}[HEADER]${NC} $1"
}

# Check if OmniScope is built
if [ ! -f "$ZIG_OUT" ]; then
    echo_error "OmniScope not found at $ZIG_OUT"
    echo_info "Building OmniScope..."
    cd "$PROJECT_ROOT"
    zig build
    echo_step "Build complete"
fi

# List available demos and tests
list_examples() {
    echo_header "=== Production Demos ==="
    echo "  demos:"
    echo "    crypto_key_manager     - Rust+C cryptography (buffer overflow, command injection)"
    echo "    web_command_injection  - Go+C HTTP server (network parser vulnerabilities)"
    echo ""
    echo_header "=== Functional Tests ==="
    echo "  tests/basic_patterns:"
    echo "    cffi_test              - Cross-language FFI test (C)"
    echo "    sample_analysis        - Memory safety issues (C)"
    echo "    sample_rust            - Rust patterns (requires rustc)"
    echo "    sample_zig             - Zig patterns (requires zig)"
    echo "    sample_go              - Go patterns (requires gollvm)"
    echo "  tests/edge_cases:"
    echo "    logic_bugs             - Logic bug patterns (C)"
    echo "    ntt                    - Number theoretic transform (C)"
    echo ""
    echo "Usage: $0 [demo_name|test_name]"
    echo "Examples:"
    echo "  $0 crypto_key_manager"
    echo "  $0 tests/basic_patterns/cffi_test"
    echo "  $0 all"
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

# Compile and run Rust+C demo
run_crypto_key_manager() {
    echo_header "=== Demo: Crypto Key Manager (Rust+C) ==="
    cd "$EXAMPLES_DIR/demos/crypto_key_manager"

    # Check for required tools
    if ! command -v rustc &> /dev/null; then
        echo_error "rustc not found. Please install Rust to run this demo."
        echo_info "Visit: https://rustup.rs/"
        return 1
    fi

    # Compile C layer
    if [ ! -f "c_vulnerable_layer.bc" ]; then
        echo_step "Compiling C layer..."
        gcc -c -emit-llvm -O0 -g c_vulnerable_layer.c -o c_vulnerable_layer.bc
    fi

    # Compile Rust layer
    if [ ! -f "rust_safe_layer.bc" ]; then
        echo_step "Compiling Rust layer..."
        rustc --crate-type=lib --emit=llvm-bc -O0 rust_safe_layer.rs -o rust_safe_layer.bc
    fi

    # Link
    if [ ! -f "combined.bc" ] || [ "c_vulnerable_layer.bc" -nt "combined.bc" ] || [ "rust_safe_layer.bc" -nt "combined.bc" ]; then
        echo_step "Linking Rust and C layers..."
        llvm-link rust_safe_layer.bc c_vulnerable_layer.bc -o combined.bc
    fi

    run_analysis "combined.bc" "crypto_key_manager"
}

# Compile and run Go+C demo
run_web_command_injection() {
    echo_header "=== Demo: Web Command Injection (Go+C) ==="
    cd "$EXAMPLES_DIR/demos/web_command_injection"

    # Check for required tools
    if ! command -v gollvm &> /dev/null && ! command -v go &> /dev/null; then
        echo_error "gollvm not found. This demo requires gollvm or go build with LLVM IR generation."
        echo_info "Visit: https://github.com/gollvm/gollvm"
        return 1
    fi

    # Compile C layer
    if [ ! -f "c_parser.bc" ]; then
        echo_step "Compiling C layer..."
        gcc -c -emit-llvm -O0 -g c_parser.c -o c_parser.bc
    fi

    # Compile Go layer
    if [ ! -f "go_http_server.bc" ]; then
        echo_step "Compiling Go layer..."
        if command -v gollvm &> /dev/null; then
            gollvm -S -emit-llvm -O0 go_http_server.go -o go_http_server.ll
            llvm-as go_http_server.ll -o go_http_server.bc
        else
            echo_info "gollvm not available, skipping Go compilation"
            echo_info "Demo requires gollvm for Go → LLVM IR generation"
            return 1
        fi
    fi

    # Link
    if [ ! -f "combined.bc" ] || [ "c_parser.bc" -nt "combined.bc" ] || [ "go_http_server.bc" -nt "combined.bc" ]; then
        echo_step "Linking Go and C layers..."
        llvm-link go_http_server.bc c_parser.bc -o combined.bc
    fi

    run_analysis "combined.bc" "web_command_injection"
}

# Run basic pattern tests
run_basic_pattern() {
    local test_name=$1
    echo_header "=== Test: $test_name ==="
    cd "$EXAMPLES_DIR/tests/basic_patterns"

    case "$test_name" in
        cffi_test|sample_analysis|ntt)
            compile_c_example "${test_name}.c"
            run_analysis "${test_name}.bc" "$test_name"
            ;;
        sample_rust)
            if ! command -v rustc &> /dev/null; then
                echo_info "Skipping sample_rust (rustc not found)"
                return
            fi
            if [ ! -f "sample_rust.bc" ]; then
                rustc --crate-type=lib --emit=llvm-bc sample_rust.rs -o sample_rust.bc
            fi
            run_analysis "sample_rust.bc" "sample_rust"
            ;;
        sample_zig)
            if ! command -v zig &> /dev/null; then
                echo_info "Skipping sample_zig (zig not found)"
                return
            fi
            if [ ! -f "sample_zig.bc" ]; then
                zig build-obj sample_zig.zig -femit-llvm=sample_zig.bc 2>/dev/null || {
                    echo_info "Zig compilation failed, skipping"
                    return
                }
            fi
            run_analysis "sample_zig.bc" "sample_zig"
            ;;
        sample_go)
            if ! command -v gollvm &> /dev/null; then
                echo_info "Skipping sample_go (gollvm not found)"
                return
            fi
            if [ ! -f "sample_go.bc" ]; then
                gollvm -S -emit=llvm-bc sample_go.go -o sample_go.bc 2>/dev/null || {
                    echo_info "Go compilation failed, skipping"
                    return
                }
            fi
            run_analysis "sample_go.bc" "sample_go"
            ;;
        *)
            echo_error "Unknown basic pattern test: $test_name"
            return 1
            ;;
    esac
}

# Run edge case tests
run_edge_case() {
    local test_name=$1
    echo_header "=== Test: $test_name ==="
    cd "$EXAMPLES_DIR/tests/edge_cases"

    case "$test_name" in
        logic_bugs)
            compile_c_example "logic_bugs.c"
            run_analysis "logic_bugs.bc" "logic_bugs"
            ;;
        *)
            echo_error "Unknown edge case test: $test_name"
            return 1
            ;;
    esac
}

# Run all demos
run_all_demos() {
    run_crypto_key_manager
    run_web_command_injection
}

# Run all tests
run_all_tests() {
    echo_header "=== Running All Basic Pattern Tests ==="
    for test in cffi_test sample_analysis sample_rust sample_zig sample_go; do
        run_basic_pattern "$test"
    done

    echo_header "=== Running All Edge Case Tests ==="
    for test in logic_bugs; do
        run_edge_case "$test"
    done
}

# Run all demos and tests
run_all() {
    run_all_demos
    run_all_tests
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
        "demos" | "demo")
            run_all_demos
            ;;
        "tests" | "test")
            run_all_tests
            ;;
        "crypto_key_manager")
            run_crypto_key_manager
            ;;
        "web_command_injection")
            run_web_command_injection
            ;;
        "cffi_test" | "sample_analysis" | "sample_rust" | "sample_zig" | "sample_go" | "ntt")
            run_basic_pattern "$1"
            ;;
        "logic_bugs")
            run_edge_case "$1"
            ;;
        "list"|"-l"|"--list")
            list_examples
            ;;
        *)
            # Try to parse as path
            if [[ "$1" == tests/* ]] || [[ "$1" == demos/* ]]; then
                local path="$EXAMPLES_DIR/$1"
                if [ -f "$path" ]; then
                    run_analysis "$path" "$1"
                elif [ -f "${path%.c}.bc" ]; then
                    run_analysis "${path%.c}.bc" "$1"
                elif [ -f "${path%.rs}.bc" ]; then
                    run_analysis "${path%.rs}.bc" "$1"
                elif [ -f "${path}.bc" ]; then
                    run_analysis "${path}.bc" "$1"
                else
                    echo_error "Unknown example or path not found: $1"
                    list_examples
                    exit 1
                fi
            else
                echo_error "Unknown example: $1"
                list_examples
                exit 1
            fi
            ;;
    esac
}

main "$@"