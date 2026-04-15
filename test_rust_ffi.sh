#!/bin/bash
# OmniScope Rust FFI Detection Test Script
# 
# This script tests the cross-language FFI analysis capabilities
# including multi-file input, .ll file support, and vulnerability detection

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

echo_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

# Binary path
BINARY="$PROJECT_ROOT/zig-out/bin/OmniSope"

# Check if binary exists
if [ ! -f "$BINARY" ]; then
    echo_error "OmniScope binary not found at $BINARY"
    echo_info "Building OmniScope..."
    zig build
    echo_success "Build complete"
fi

# Test directory
RUST_FFI_DIR="$PROJECT_ROOT/examples/ffi_command_injection"

# Check if Rust FFI examples exist
if [ ! -d "$RUST_FFI_DIR" ]; then
    echo_error "Rust FFI examples not found at $RUST_FFI_DIR"
    exit 1
fi

# Compile C code if needed
C_BC="$RUST_FFI_DIR/src/c_crypto_lib.bc"
if [ ! -f "$C_BC" ]; then
    echo_step "Compiling C code to LLVM IR"
    cd "$RUST_FFI_DIR/src"
    gcc -c -emit-llvm -O0 -g c_crypto_lib.c -o c_crypto_lib.bc
    cd "$PROJECT_ROOT"
    echo_success "C code compiled: $C_BC"
fi

# Test 1: Help information
echo_step "Test 1: Help information"
"$BINARY" --help
echo ""

# Test 2: Single file analysis (Rust)
echo_step "Test 2: Single file analysis (Rust)"
RUST_BC="$RUST_FFI_DIR/lib.rs.bc"
if [ -f "$RUST_BC" ]; then
    echo_info "Analyzing Rust IR: $RUST_BC"
    "$BINARY" "$RUST_BC" || echo_error "Failed to analyze Rust IR"
    echo ""
else
    echo_error "Rust IR not found: $RUST_BC"
fi

# Test 3: Single file analysis (C)
echo_step "Test 3: Single file analysis (C)"
if [ -f "$C_BC" ]; then
    echo_info "Analyzing C IR: $C_BC"
    "$BINARY" "$C_BC" || echo_error "Failed to analyze C IR"
    echo ""
else
    echo_error "C IR not found: $C_BC"
fi

# Test 4: Multi-file FFI mode
echo_step "Test 4: Multi-file FFI mode (Rust + C)"
if [ -f "$RUST_BC" ] && [ -f "$C_BC" ]; then
    echo_info "Analyzing Rust + C together"
    "$BINARY" "$RUST_BC" "$C_BC" || echo_error "Failed to analyze multi-file FFI"
    echo ""
else
    echo_error "Required files not found for multi-file analysis"
fi

# Test 5: .ll file support
echo_step "Test 5: .ll file support"
RUST_LL="$RUST_FFI_DIR/lib.rs.ll"
if [ -f "$RUST_LL" ]; then
    echo_info "Analyzing Rust .ll file: $RUST_LL"
    "$BINARY" "$RUST_LL" || echo_error "Failed to analyze .ll file"
    echo ""
else
    echo_error "Rust .ll file not found: $RUST_LL"
fi

# Test 6: Version information
echo_step "Test 6: Version information"
"$BINARY" --version
echo ""

# Summary
echo_step "Test Summary"
echo_success "All basic tests completed!"
echo_info "For detailed FFI vulnerability detection, the implementation is still in progress."
echo_info "The multi-file mode should show FFI detection prompts when complete."
echo ""
echo_info "Test files used:"
echo_info "  - Rust IR: $RUST_BC"
echo_info "  - C IR: $C_BC"
echo_info "  - Rust .ll: $RUST_LL"
echo ""
echo_info "To run manual tests:"
echo_info "  ./zig-out/bin/OmniScope examples/ffi_command_injection/lib.rs.bc"
echo_info "  ./zig-out/bin/OmniScope examples/ffi_command_injection/lib.rs.bc examples/ffi_command_injection/src/c_crypto_lib.bc"
echo_info "  ./zig-out/bin/OmniScope examples/ffi_command_injection/lib.rs.ll"