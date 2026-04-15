#!/bin/bash
# OmniScope Demo Runner - Run from project root

echo "=== OmniScope Demo Runner ==="
echo "Run cross-language vulnerability detection demos"
echo ""

if [ ! -f "zig-out/bin/OmniSope" ]; then
    echo "Building OmniScope..."
    zig build
    echo "✓ Build complete"
    echo ""
fi

# Run the demo script
./examples/demos/run_demo.sh