#!/bin/bash
# OmniScope Benchmark Runner Script
# Usage: ./run_benchmarks.sh [benchmark_name]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_step() {
    echo -e "${GREEN}[BENCH]${NC} $1"
}

echo_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Build test flags
ZIG_FLAGS="-lz -lLLVM-22 -I /opt/homebrew/Cellar/llvm/22.1.3/include -L /opt/homebrew/Cellar/llvm/22.1.3/lib -rpath /opt/homebrew/Cellar/llvm/22.1.3/lib"

# List available benchmarks
list_benchmarks() {
    echo "Available benchmarks:"
    echo "  1. all           - Run all benchmarks"
    echo "  2. fact_store    - FactStore insert/query performance"
    echo "  3. taint         - TaintContext operations"
    echo "  4. ffi           - FFIBoundaryDetector operations"
    echo "  5. flow_path     - FlowPath operations"
    echo "  6. concurrent    - Concurrent FactStore inserts"
    echo "  7. call_graph    - Call graph building"
    echo "  8. risk          - RiskLevel classification"
    echo ""
    echo "Usage: $0 [benchmark_name]"
}

# Get test filter for specific benchmark
get_filter() {
    case "$1" in
        "fact_store")
            echo "Benchmark - FactStore"
            ;;
        "taint")
            echo "Benchmark - TaintContext"
            ;;
        "ffi")
            echo "Benchmark - FFIBoundaryDetector"
            ;;
        "flow_path")
            echo "Benchmark - FlowPath"
            ;;
        "concurrent")
            echo "Benchmark - Concurrent"
            ;;
        "call_graph")
            echo "Benchmark - CallGraph"
            ;;
        "risk")
            echo "Benchmark - RiskLevel"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Run a specific benchmark test
run_benchmark() {
    local name=$1
    local filter=$(get_filter "$name")

    echo_step "Running benchmark: $name"

    cd "$PROJECT_ROOT"

    if [ -n "$filter" ]; then
        # Run specific test
        zig test src/root.zig $ZIG_FLAGS --test-filter "$filter" 2>&1 || {
            echo_error "Benchmark failed: $name"
            return 1
        }
    else
        # Run all benchmarks
        zig test src/root.zig $ZIG_FLAGS --test-filter "Benchmark" 2>&1 || {
            echo_error "Benchmarks failed"
            return 1
        }
    fi

    echo_info "Completed: $name"
    echo ""
}

# Run all benchmarks
run_all() {
    echo_step "Running all benchmarks..."
    echo ""

    cd "$PROJECT_ROOT"

    # Run FactStore benchmarks
    run_benchmark "fact_store"
    run_benchmark "taint"
    run_benchmark "ffi"
    run_benchmark "flow_path"
    run_benchmark "concurrent"
    run_benchmark "call_graph"
    run_benchmark "risk"

    echo_step "=== All benchmarks complete ==="
}

# Quick benchmark (shorter tests)
run_quick() {
    echo_step "Running quick benchmarks..."
    echo ""

    cd "$PROJECT_ROOT"

    # Just run without filter to see all benchmark names
    zig test src/root.zig $ZIG_FLAGS --test-filter "Benchmark" 2>&1 | grep -E "^(test|Benchmark)" | head -20 || true

    echo ""
    echo_info "Quick mode complete. Run with specific benchmark name for detailed results."
}

# Main
main() {
    echo "OmniScope Benchmark Runner"
    echo "=========================="
    echo ""

    # Check for LLVM
    if [ ! -d "/opt/homebrew/Cellar/llvm/22.1.3" ]; then
        echo_error "LLVM 22 not found at /opt/homebrew/Cellar/llvm/22.1.3"
        echo_info "Please install LLVM or update the LLVM path in this script"
        exit 1
    fi

    case "${1:-}" in
        "" | "all")
            run_all
            ;;
        "quick")
            run_quick
            ;;
        "list"|"-l"|"--list")
            list_benchmarks
            ;;
        "fact_store"|"taint"|"ffi"|"flow_path"|"concurrent"|"call_graph"|"risk")
            run_benchmark "$1"
            ;;
        *)
            echo_error "Unknown benchmark: $1"
            list_benchmarks
            exit 1
            ;;
    esac
}

main "$@"
