#!/bin/bash
# baseline_check.sh - Real-world project regression guard
#
# Validates that OmniScope output matches BASELINE.md expectations.
# Run via: make baseline-check
#
# Exit codes:
#   0 = All baselines passed
#   1 = One or more regressions detected

set -euo pipefail

OMNISCOPE="./zig-out/bin/omniscope"
CORPUS_DIR="corpus/real_world"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

header() {
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${RESET}"
    printf "${BOLD}║%58s║${RESET}\n" "$1"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${RESET}"
}

check_rule() {
    local name="$1" expected="$2" actual="$3" strict="$4"
    if [ "$strict" = "strict" ]; then
        if [ "$actual" != "$expected" ]; then
            echo -e "  ${RED}✗ FAIL${RESET} $name: expected=$expected actual=$actual"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            return 1
        fi
    elif [ "$strict" = "min" ]; then
        # min: actual must be >= expected (test files should find at least N bugs)
        if [ "$actual" -lt "$expected" ]; then
            echo -e "  ${RED}✗ UNDER-DETECTION${RESET} $name: expected≥$expected actual=$actual"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            return 1
        fi
        if [ "$actual" -gt "$expected" ]; then
            echo -e "  ${GREEN}✓ OVER-DETECTED${RESET} $name: expected≥$expected actual=$actual"
            WARN_COUNT=$((WARN_COUNT + 1))
            return 0
        fi
    else
        # max (non-strict): actual must be <= expected (allow improvement)
        if [ "$actual" -gt "$expected" ]; then
            echo -e "  ${RED}✗ REGRESSION${RESET} $name: max=$expected actual=$actual"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            return 1
        fi
        if [ "$actual" -lt "$expected" ]; then
            echo -e "  ${GREEN}✓ IMPROVED${RESET} $name: was≤$expected now=$actual"
            WARN_COUNT=$((WARN_COUNT + 1))
            return 0
        fi
    fi
    echo -e "  ${GREEN}✓ PASS${RESET} $name: $actual"
    PASS_COUNT=$((PASS_COUNT + 1))
    return 0
}

run_project() {
    local name="$1" ir_file="$2"
    shift 2
    local rules=("$@")

    echo ""
    echo -e "${BOLD}── $name ──${RESET}"
    echo "  IR: $ir_file"

    if [ ! -f "$ir_file" ]; then
        echo -e "  ${YELLOW}⚠ SKIP${RESET} IR file not found: $ir_file"
        return 0
    fi

    local start_time
    start_time=$(python3 -c 'import time; print(time.time())' 2>/dev/null || date +%s)

    local output
    output=$("$OMNISCOPE" "$ir_file" 2>&1) || true

    local end_time
    end_time=$(python3 -c 'import time; print(time.time())' 2>/dev/null || date +%s)
    local elapsed
    elapsed=$(python3 -c "print('%.2f' % ($end_time - $start_time))" 2>/dev/null || echo "?")

    local total_issues ffi_risks leaks null_derefs
    total_issues=$(echo "$output" | grep -c "Issues detected:" || true)
    if [ "$total_issues" -gt 0 ]; then
        total_issues=$(echo "$output" | grep "Issues detected:" | awk '{print $NF}')
    else
        total_issues=0
    fi

    leaks=$(echo "$output" | grep -c "MEMORY LEAK" || true)
    null_derefs=$(echo "$output" | grep -c "null_dereference" || true)
    ffi_risks=$(echo "$output" | grep -c "FFI RISK\|Dangerous calls" || true)

    # Extract issue count from "Issues detected: N" line
    local detected_count
    detected_count=$(echo "$output" | grep "Issues detected:" | awk '{print $NF}' || echo "0")

    echo "  Results: issues=$detected_count leak=$leaks null_deref=$null_derefs time=${elapsed}s"

    for rule_spec in "${rules[@]}"; do
        IFS=':' read -r rule_name rule_type rule_expected <<< "$rule_spec"
        case "$rule_name" in
            total) check_rule "Total Issues" "$rule_expected" "$detected_count" "$rule_type" ;;
            leak)  check_rule "Memory Leaks" "$rule_expected" "$leaks" "$rule_type" ;;
            null_deref) check_rule "Null Deref" "$rule_expected" "$null_derefs" "$rule_type" ;;
            time)  check_rule "Time (s)" "$rule_expected" "$(printf '%.*f' 0 "$elapsed")" "$rule_type" ;;
        esac
    done
}

# ========================================
# Main
# ========================================

echo ""
echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════════╗${RESET}"
printf "${BOLD}${GREEN}║%58s║${RESET}\n" "BASELINE REGRESSION CHECK"
echo -e "${BOLD}${GREEN}╠════════════════════════════════════════════════════════════════╣${RESET}"
printf "${BOLD}${GREEN}║%-58s║${RESET}\n" "Validating against corpus/real_world/BASELINE.md"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════════╝${RESET}"

if [ ! -x "$OMNISCOPE" ]; then
    echo -e "${RED}Error: $OMNISCOPE not found. Run 'make build' first.${RESET}"
    exit 1
fi

# SQLite rules: total≤15, leak=0(strict), null_deref=0(strict), time≤15
run_project "SQLite 3.47.2" "$CORPUS_DIR/sqlite3.ll" \
    "total:max:15" "leak:strict:0" "null_deref:strict:0" "time:max:15"

# libcurl rules: total≤5, leak=0(strict), time<1
run_project "libcurl 8.14.0" "$CORPUS_DIR/curl8.ll" \
    "total:max:5" "leak:strict:0" "time:max:1"

# libuv rules: total≤5, leak=0(strict), time<1
run_project "libuv 1.50.0" "$CORPUS_DIR/libuv150.ll" \
    "total:max:5" "leak:strict:0" "time:max:1"

# jsoncpp rules: total≤10, leak=0(strict), null_deref=0(strict), time≤5
run_project "jsoncpp 1.9.5" "$CORPUS_DIR/jsoncpp195.ll" \
    "total:max:10" "leak:strict:0" "null_deref:strict:0" "time:max:5"

# abseil-cpp rules: total≤15, null_deref=0(strict), time≤2
run_project "abseil-cpp 2024" "$CORPUS_DIR/abseil2024.ll" \
    "total:max:15" "null_deref:strict:0" "time:max:2"

# ripgrep 14.1.1 (Rust): total≤5, leak=0(strict), time≤2
run_project "ripgrep 14.1.1 (Rust)" "$CORPUS_DIR/ripgrep141.ll" \
    "total:max:5" "leak:strict:0" "time:max:2"

# rust_sqlite_ffi (Rust test): total≤15, leak≤10 (non-strict), time≤5
run_project "rust-sqlite-ffi (Rust test)" "$CORPUS_DIR/rust_sqlite.ll" \
    "total:max:15" "leak:max:10" "time:max:5"

# openssl_wrapper (C crypto test): total≤25, leak≥5, time≤1
run_project "openssl_wrapper (crypto test)" "$CORPUS_DIR/openssl_wrapper.ll" \
    "total:max:25" "leak:min:5" "time:max:1"

# wasmtime_test (Rust+C FFI): total≤50, leak=0(strict), time≤30
run_project "wasmtime_test (Rust+C FFI)" "$CORPUS_DIR/wasmtime_test.ll" \
    "total:max:50" "leak:strict:0" "time:max:30"

# wabt_wast2json (C++ WebAssembly Toolkit): total≤10, leak≤5, time≤1
run_project "wabt_wast2json (C++ WasmToolkit)" "$CORPUS_DIR/wabt_wast2json.ll" \
    "total:max:10" "leak:max:5" "time:max:1"

# Summary
echo ""
echo -e "${BOLD}═════════════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD} SUMMARY${RESET}"
echo -e "  ${GREEN}Passed:${RESET}  $PASS_COUNT"
if [ "$WARN_COUNT" -gt 0 ]; then
    echo -e "  ${YELLOW}Improved:${RESET} $WARN_COUNT"
fi
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo -e "  ${RED}Failed/Regressed:${RESET}  $FAIL_COUNT"
fi
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo -e "${RED}${BOLD}✗ BASELINE CHECK FAILED — $FAIL_COUNT regression(s) detected${RESET}"
    exit 1
else
    echo -e "${GREEN}${BOLD}✓ ALL BASELINES PASSED${RESET}"
    exit 0
fi
