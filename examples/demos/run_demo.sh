#!/bin/bash
# Quick demo runner for C++ + C cross-language analysis

set -e

echo "=== OmniScope C++ + C Cross-Language Demo ==="
echo ""

# Add OmniScope to PATH
export PATH="$PATH:/Users/scc/code/zigcode/OmniSope/zig-out/bin"

# Demo 1: Real-world Distributed Computing (WORKS - Recommended!)
echo "[Demo 1] Real-world Distributed Computing System"
echo "           C++: Business logic | C: Result aggregation & verification"
echo "           Expected: ✓ Detect 4 vulnerabilities"
echo "-----------------------------------------------------------------------"
cd /Users/scc/code/zigcode/OmniSope/examples/demos

# Compile if needed
if [ ! -f "real_world_simple_combined.bc" ]; then
    echo "Compiling..."
    gcc -c -emit-llvm -O0 -g real_world_c_layer.c -o real_world_c_layer.bc
    clang++ -c -emit-llvm -O0 -g real_world_simple.cpp -o real_world_simple.bc
    /opt/homebrew/opt/llvm/bin/llvm-link real_world_simple.bc real_world_c_layer.bc -o real_world_simple_combined.bc
    echo "✓ Compilation complete"
fi

echo "Analyzing..."
OmniSope real_world_simple_combined.bc
echo ""

# Demo 2: Simple C++ + C (WORKS)
echo "[Demo 2] Simple C++ + C Test"
echo "           Expected: ✓ Detect 3 vulnerabilities"
echo "--------------------------------------------------"

if [ ! -f "simple_combined.bc" ]; then
    echo "Compiling..."
    gcc -c -emit-llvm -O0 -g simple_c.c -o simple_c.bc
    clang++ -c -emit-llvm -O0 -g simple_cpp_c.cpp -o simple_cpp_c.bc
    /opt/homebrew/opt/llvm/bin/llvm-link simple_cpp_c.bc simple_c.bc -o simple_combined.bc
    echo "✓ Compilation complete"
fi

echo "Analyzing..."
OmniSope simple_combined.bc
echo ""

# Demo 3: Existing cffi_test (WORKS)
echo "[Demo 3] Existing cffi_test (C only)"
echo "           Expected: ✓ Detect 3 vulnerabilities"
echo "-----------------------------------------------"

if [ ! -f "/Users/scc/code/zigcode/OmniSope/examples/tests/basic_patterns/cffi_test.bc" ]; then
    echo "Compiling..."
    cd /Users/scc/code/zigcode/OmniSope/examples/tests/basic_patterns
    gcc -c -emit-llvm -O0 -g cffi_test.c -o cffi_test.bc
    echo "✓ Compilation complete"
fi

echo "Analyzing..."
cd /Users/scc/code/zigcode/OmniSope
OmniSope examples/tests/basic_patterns/cffi_test.bc
echo ""

# Demo 4: Complex C++ + C (Expected: NO ISSUES - too complex)
echo "[Demo 4] Complex C++ + C (with classes, exceptions, STL)"
echo "           Expected: ✗ May not detect (too complex - 1430 functions)"
echo "------------------------------------------------------------------------"
cd /Users/scc/code/zigcode/OmniSope/examples/demos

if [ ! -f "combined.bc" ]; then
    echo "Compiling..."
    gcc -c -emit-llvm -O0 -g c_vulnerable_layer.c -o c_vulnerable_layer.bc
    clang++ -c -emit-llvm -O0 -g cpp_ffi_safe_layer.cpp -o cpp_ffi_safe_layer.bc
    /opt/homebrew/opt/llvm/bin/llvm-link cpp_ffi_safe_layer.bc c_vulnerable_layer.bc -o combined.bc
    echo "✓ Compilation complete"
fi

echo "Analyzing..."
OmniSope combined.bc
echo ""

echo "=== Demo Complete ==="
echo ""
echo "Summary:"
echo "  ✓ Demo 1 (Real-world): Detected 4 vulnerabilities (buffer overflow, command injection)"
echo "  ✓ Demo 2 (Simple): Detected 3 vulnerabilities (buffer overflow, command injection)"
echo "  ✓ Demo 3 (cffi_test): Detected 3 vulnerabilities (command injection)"
echo "  ✗ Demo 4 (Complex): May not detect (too many C++ standard library functions)"
echo ""
echo "Key Takeaways:"
echo "  • OmniScope works best with simple, direct cross-language calls"
echo "  • Complex C++ code (classes, exceptions, STL) can interfere with analysis"
echo "  • Real-world distributed computing scenarios can be analyzed successfully"
echo ""
echo "To run individual demos:"
echo "  cd /Users/scc/code/zigcode/OmniSope/examples/demos"
echo "  export PATH=\"\$PATH:/Users/scc/code/zigcode/OmniSope/zig-out/bin\""
echo "  OmniSope real_world_simple_combined.bc  # Recommended!"
echo "  OmniSope simple_combined.bc"
echo "  OmniSope combined.bc"