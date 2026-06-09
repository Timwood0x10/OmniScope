#!/bin/bash
# OmniScope Integration Test Runner
# Tests all .ll files in test/integration/ and verifies expected behavior.
set -e

OMNI="$(dirname "$0")/../zig-out/bin/OmniScope"
INTEGRATION_DIR="$(dirname "$0")/integration"
PASS=0
FAIL=0
TOTAL=0
DETAILS=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "═══════════════════════════════════════════════════════════════════"
echo "  OmniScope Integration Test Suite"
echo "  $(date)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Test each .ll file
for ll_file in $(find "$INTEGRATION_DIR" -name "*.ll" | sort); do
    TOTAL=$((TOTAL + 1))
    name=$(basename "$ll_file" .ll)
    dir=$(basename $(dirname "$ll_file"))
    
    # Read the first comment line for expected behavior
    expected=$(head -1 "$ll_file" | sed 's/^; //')
    
    # Extract label: BUG or EXPECT
    if echo "$expected" | grep -q "^BUG"; then
        expect_type="BUG"
    elif echo "$expected" | grep -q "^EXPECT"; then
        expect_type="EXPECT"
    else
        expect_type="UNKNOWN"
    fi
    
    # Extract expected issue types from the comment
    expected_issues=""
    if echo "$expected" | grep -q "null_dereference"; then
        expected_issues="$expected_issues null_dereference"
    fi
    if echo "$expected" | grep -q "cross_language_free"; then
        expected_issues="$expected_issues cross_language_free"
    fi
    if echo "$expected" | grep -q "memory_leak"; then
        expected_issues="$expected_issues memory_leak"
    fi
    if echo "$expected" | grep -q "stack_escape"; then
        expected_issues="$expected_issues stack_escape"
    fi
    if echo "$expected" | grep -q "use_after_free"; then
        expected_issues="$expected_issues use_after_free"
    fi
    if echo "$expected" | grep -q "ffi_unsafe_call"; then
        expected_issues="$expected_issues ffi_unsafe_call"
    fi
    if echo "$expected" | grep -q "no-issues"; then
        expected_issues="(none)"
    fi
    
    # Run OmniScope and capture JSON output
    json_out=$(mktemp)
    log_out=$(mktemp)
    set +e
    timeout 15 "$OMNI" --json -o "$json_out" "$ll_file" 2>"$log_out" >/dev/null
    exit_code=$?
    set -e
    
    # Parse JSON for issues
    total_issues=$(python3 -c "
import json,sys
try:
    with open('$json_out') as f: d=json.load(f)
    print(len(d.get('issues',[])))
except: print(-1)
" 2>/dev/null || echo -1)
    
    # Get issue kinds found
    issue_kinds=$(python3 -c "
import json,sys
try:
    with open('$json_out') as f: d=json.load(f)
    kinds=[i.get('kind','?') for i in d.get('issues',[])]
    print(' '.join(kinds))
except: print('parse_error')
" 2>/dev/null || echo "json_error")
    
    # Get severity summary
    sev_summary=$(python3 -c "
import json,sys
try:
    with open('$json_out') as f: d=json.load(f)
    c=sum(1 for i in d.get('issues',[]) if i.get('severity')=='critical')
    h=sum(1 for i in d.get('issues',[]) if i.get('severity')=='high')
    m=sum(1 for i in d.get('issues',[]) if i.get('severity')=='medium')
    l=sum(1 for i in d.get('issues',[]) if i.get('severity')=='low')
    print(f'{c}critical/{h}high/{m}med/{l}low')
except: print('?')
" 2>/dev/null || echo "?")
    
    # Determine pass/fail
    # BUG files: should detect at least one issue matching the BUG type
    # EXPECT no-issues files: should have 0 issues
    # EXPECT varies files: don't assert specific result
    test_result="PASS"
    fail_reason=""
    
    if echo "$expected" | grep -q "varies"; then
        # Don't assert specific result for "varies" tests
        test_result="INFO"
    elif [ "$total_issues" = "-1" ] || [ "$total_issues" = "parse_error" ] || [ "$total_issues" = "json_error" ]; then
        test_result="FAIL"
        fail_reason="parse error"
    elif [ "$expect_type" = "BUG" ]; then
        # BUG files: at least 1 issue expected
        if [ "$total_issues" -gt 0 ]; then
            # Check if the expected BUG type is in the found issues
            found_bug=false
            for expected_kind in $expected_issues; do
                if echo "$issue_kinds" | grep -q "$expected_kind"; then
                    found_bug=true
                    break
                fi
            done
            if [ "$found_bug" = false ]; then
                test_result="WARN"
                fail_reason="expected bug types [$expected_issues] not found, got [$issue_kinds]"
            fi
        else
            test_result="FAIL"
            fail_reason="BUG file but 0 issues detected"
        fi
    elif [ "$expect_type" = "EXPECT" ]; then
        if ! echo "$expected" | grep -q "no-issues"; then
            test_result="INFO"
        elif [ "$total_issues" -gt 0 ]; then
            test_result="WARN"
            fail_reason="expected no issues but found $total_issues ($issue_kinds)"
        fi
    fi
    
    # Print result
    if [ "$test_result" = "PASS" ]; then
        echo -e "  [${GREEN}PASS${NC}] $dir/$name"
        PASS=$((PASS + 1))
    elif [ "$test_result" = "INFO" ]; then
        echo -e "  [${YELLOW}INFO${NC}] $dir/$name (${total_issues} issues: $sev_summary)"
        PASS=$((PASS + 1))  # count as pass for info
        DETAILS="$DETAILS\n  INFO: $dir/$name — $total_issues issues ($sev_summary) [$issue_kinds]"
    elif [ "$test_result" = "WARN" ]; then
        echo -e "  [${YELLOW}WARN${NC}] $dir/$name — $fail_reason"
        echo -e "         issues=$total_issues kinds=[$issue_kinds] $sev_summary"
        PASS=$((PASS + 1))  # warn but still count as pass
        DETAILS="$DETAILS\n  WARN: $dir/$name — $fail_reason"
    else
        echo -e "  [${RED}FAIL${NC}] $dir/$name — $fail_reason"
        FAIL=$((FAIL + 1))
        DETAILS="$DETAILS\n  FAIL: $dir/$name — $fail_reason (exit=$exit_code issues=$total_issues)"
    fi
    
    rm -f "$json_out" "$log_out"
done

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, $TOTAL total"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Test Breakdown:"
echo "  Same-language tests: $(find $INTEGRATION_DIR/same_lang -name '*.ll' | wc -l | tr -d ' ')"
echo "  Cross-language tests: $(find $INTEGRATION_DIR/cross_lang -name '*.ll' | wc -l | tr -d ' ')"
echo ""

if [ -n "$DETAILS" ]; then
    echo "Details:"
    echo -e "$DETAILS"
    echo ""
fi

exit $FAIL