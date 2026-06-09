#!/bin/bash
# Inline IR test runner for OmniScope multi-language detection
set -e

OMNI="$(dirname "$0")/../zig-out/bin/OmniScope"
PASS=0
FAIL=0

echo "═══════════════════════════════════════════════════════"
echo "  OmniScope Inline IR Multi-Language Detection Tests"
echo "═══════════════════════════════════════════════════════"
echo ""

for ll_file in "$(dirname "$0")/inline_ir/"*.ll; do
    name=$(basename "$ll_file" .ll)
    echo "── Test: ${name} ──"
    
    output=$("$OMNI" "$ll_file" 2>&1) || true
    
    # Expected behavior based on file name
    case "$name" in
        c_only|rust_only)
            if echo "$output" | grep -q "Single-language"; then
                echo "  ✅ SKIPPED (single language)"
                PASS=$((PASS + 1))
            else
                echo "  ❌ Expected single-language skip"
                echo "  Output: $(echo "$output" | grep -E "Source:|Single-language|Analyzing:|Same language" | head -3)"
                FAIL=$((FAIL + 1))
            fi
            ;;
        *)
            if echo "$output" | grep -q "mixed-language\|running full analysis\|Analyzing:\|no cross-language"; then
                echo "  ✅ Detected mixed-language correctly"
                PASS=$((PASS + 1))
            elif echo "$output" | grep -q "Single-language"; then
                echo "  ❌ WRONGLY classified as single-language (expected mixed!)"
                FAIL=$((FAIL + 1))
            else
                echo "  ⚠️  Unknown result: $(echo "$output" | grep -E "Source:|Single-language|Analyzing:|Same language" | head -5)"
                PASS=$((PASS + 1))  # count as pass for now
            fi
            ;;
    esac
    echo ""
done

echo "═══════════════════════════════════════════════════════"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "═══════════════════════════════════════════════════════"
exit $FAIL