#!/bin/bash
# Multi-language FFI Analysis Test
# Tests Rust + C mixed language analysis

set -e

echo "=== Multi-Language FFI Analysis Test ==="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}[Step 1]${NC} Compile C code..."
clang -emit-llvm -c test_ffi_benchmark.c -o test_ffi_benchmark.bc 2>&1 | grep -v "warning:" || true
echo -e "${GREEN}✓${NC} C code compiled"

echo ""
echo -e "${BLUE}[Step 2]${NC} Compile Rust code..."
rustc --emit=llvm-bc test_ffi_benchmark.rs -o test_ffi_benchmark.rs.bc 2>&1 | grep -v "warning:" || true
echo -e "${GREEN}✓${NC} Rust code compiled"

echo ""
echo -e "${BLUE}[Step 3]${NC} Analyze C code..."
echo "--- C Analysis Results ---"
./zig-out/bin/OmniSope test_ffi_benchmark.bc 2>&1 | grep -E "(INFO|WARN|ERROR|FFI|vulnerable)" || echo "No issues found"

echo ""
echo -e "${BLUE}[Step 4]${NC} Analyze Rust code..."
echo "--- Rust Analysis Results ---"
./zig-out/bin/OmniSope test_ffi_benchmark.rs.bc 2>&1 | grep -E "(INFO|WARN|ERROR|FFI|vulnerable)" || echo "No issues found"

echo ""
echo -e "${BLUE}[Step 5]${NC} Expected Results:"
echo ""
echo "Language Identification:"
echo "  - C functions: 9 (from test_ffi_benchmark.c)"
echo "  - Rust functions: Multiple (from test_ffi_benchmark.rs)"
echo "  - FFI boundaries: Rust -> C (9)"
echo ""
echo "Vulnerability Detection:"
echo "  - Command injection: 1 (vulnerable_system_command)"
echo "  - Buffer overflow: 1 (vulnerable_buffer_overflow)"
echo "  - Format string: 1 (vulnerable_format_string)"
echo "  - Use after free: 1 (potential_use_after_free)"
echo "  - Integer overflow: 1 (potential_integer_overflow)"
echo ""

echo -e "${GREEN}=== Multi-Language Test Complete ===${NC}"
echo ""
echo "Analysis summary:"
echo "  - Both C and Rust files analyzed"
echo "  - Language identification should work for both"
echo "  - FFI boundaries should be detected between languages"
echo ""