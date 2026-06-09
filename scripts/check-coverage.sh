#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║         OmniScope Test Coverage Checker                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

MODULE_LIST=(
    "src/semantics/patterns/interior_mut.zig:39"
    "src/pass/analysis/noise/issue_suppression.zig:18"
    "tests/into_raw_gate_test.zig:14"
    "src/pass/filter/issue_gate.zig:8"
    "tests/main.zig:50"
    "src/lifetime/boundary.zig:15"
    "src/dataflow/graph.zig:12"
    "src/pass/analysis/call_graph.zig:25"
)

TOTAL_EXPECTED=0
TOTAL_FOUND=0
COVERAGE_OK=true

printf "%-50s │ %8s │ %10s │ %s\n" "Module" "Expected" "Found" "Status"
echo "─────────────────────────────────────────────────────────────────────────"

for entry in "${MODULE_LIST[@]}"; do
    module="${entry%%:*}"
    expected="${entry##*:}"
    
    if [ -f "$module" ]; then
        found=$(grep -c 'test "' "$module" 2>/dev/null)
        found=${found:-0}
        TOTAL_EXPECTED=$((TOTAL_EXPECTED + expected))
        TOTAL_FOUND=$((TOTAL_FOUND + found))
        
        if [ "$found" -ge "$expected" ]; then
            status="✅ OK"
            printf "%-50s │ %8d │ %10d │ %s\n" "$module" "$expected" "$found" "$status"
        else
            status="⚠️  LOW"
            printf "%-50s │ %8d │ %10d │ %s\n" "$module" "$expected" "$found" "$status"
            COVERAGE_OK=false
        fi
    else
        status="❌ MISSING"
        printf "%-50s │ %8d │ %8s │ %s\n" "$module" "$expected" "N/A" "$status"
        COVERAGE_OK=false
    fi
done

echo ""
echo "========================================="
echo " Global Statistics"
echo "========================================="

TOTAL_MODULES=$(find src tests -name "*.zig" 2>/dev/null | wc -l | tr -d ' ')
TEST_FILES=$(find src tests -name "*.zig" -exec grep -l 'test "' {} \; 2>/dev/null | wc -l | tr -d ' ')
GLOBAL_TEST_COUNT=$(find src tests -name "*.zig" -exec grep -c 'test "' {} \; 2>/dev/null | awk -F: '{sum += $2} END {print sum+0}')

echo ""
printf "%-40s: %d\n" "Total .zig files" "$TOTAL_MODULES"
printf "%-40s: %d\n" "Files with tests" "$TEST_FILES"
printf "%-40s: ~%d (estimated)\n" "Total test blocks" "$GLOBAL_TEST_COUNT"
printf "%-40s: %d / %d\n" "Key module coverage" "$TOTAL_FOUND" "$TOTAL_EXPECTED"

if [ "$TOTAL_EXPECTED" -gt 0 ]; then
    COVERAGE_PCT=$((TOTAL_FOUND * 100 / TOTAL_EXPECTED))
    printf "%-40s: %d%%\n" "Coverage ratio" "$COVERAGE_PCT"
fi

echo ""

if [ "$COVERAGE_OK" = true ]; then
    echo "✅ Coverage check passed"
    exit 0
else
    echo "⚠️  Some modules below expected test count"
    exit 1
fi
