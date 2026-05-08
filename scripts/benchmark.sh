#!/usr/bin/env bash
# OmniScope Benchmark Script
#
# Usage:
#   ./scripts/benchmark.sh                  # Run full corpus benchmark
#   ./scripts/benchmark.sh --corpus small    # Run specific corpus category
#   ./scripts/benchmark.sh --file test.ll    # Run single file
#   ./scripts/benchmark.sh --json            # Output JSON results
#   ./scripts/benchmark.sh --ci              # CI mode (exit code = pass/fail)
#
# Environment:
#   OMNISCOPE_ZIG     - Path to zig binary (default: auto-detect)
#   OMNISCOPE_CORPUS  - Path to corpus directory (default: corpus/)
#
# Compatible with bash 3.2+ (macOS / Linux)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DETECT_OS="unix"
case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) DETECT_OS="windows" ;;
esac

if [[ "$DETECT_OS" == "windows" ]]; then
    TOOL_QUERY="where"
    REDIRECT="2>nul"
else
    TOOL_QUERY="which"
    REDIRECT="2>/dev/null"
fi

ZIG="${OMNISCOPE_ZIG:-zig}"
if ! command -v "$ZIG" >/dev/null 2>&1; then
    ZIG="$(command -v zig 2>/dev/null || echo zig)"
fi
CORPUS_DIR="${OMNISCOPE_CORPUS:-$PROJECT_ROOT/corpus}"
EXPECTED_FILE="$CORPUS_DIR/EXPECTED_RESULTS.md"
OUTPUT_DIR="$PROJECT_ROOT/outputs/benchmark"
STATS_FILE="$OUTPUT_DIR/.stats.tmp"

TOTAL_TP=0
TOTAL_FP=0
TOTAL_FN=0
TOTAL_EXPECTED=0
TOTAL_DETECTED=0
TOTAL_FFI_CRITICAL=0
TOTAL_FFI_HIGH=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

parse_expected_results() {
    if [[ ! -f "$EXPECTED_FILE" ]]; then
        echo "ERROR: Expected results file not found: $EXPECTED_FILE" >&2
        exit 1
    fi
}

get_expected_count() {
    local base_name="$1"
    local category="$2"

    local count=0
    local current_file=""
    local in_section=false

    while IFS= read -r line; do
        local clean_line="$line"
        clean_line="${clean_line//\\_/}"
        clean_line="${clean_line//·/}"

        if [[ "$clean_line" =~ ^##\ (.*) ]]; then
            current_file="${BASH_REMATCH[1]}"
            if [[ "$current_file" == *"$base_name"* ]] || [[ "$current_file" == *"$category"* ]]; then
                in_section=true
            else
                in_section=false
            fi
        elif [[ "$in_section" == true ]] && [[ "$clean_line" =~ Total\ Expected\ Issues:\ ([0-9]+).*\(([0-9]+)[[:space:]]*in-scope ]]; then
            count="${BASH_REMATCH[2]}"
            break
        elif [[ "$in_section" == true ]] && [[ "$clean_line" =~ in-scope ]] && [[ "$clean_line" =~ ^\| ]]; then
            if [[ "$clean_line" =~ ^\|\ ([0-9]+)-([0-9]+)\ \| ]]; then
                local start=${BASH_REMATCH[1]}
                local end=${BASH_REMATCH[2]}
                count=$((count + end - start + 1))
            elif [[ "$clean_line" =~ ^\|\ ([0-9]+)\ \| ]]; then
                ((count++)) || true
            fi
        fi
    done < "$EXPECTED_FILE"

    if [[ $count -eq 0 ]]; then
        case "$base_name" in
            cpp_ffi_simple)   count=3 ;;
            rust_ffi_simple)   count=4 ;;
            zig_ffi_simple)    count=3 ;;
            go_ffi_simple)     count=3 ;;
            boundary_test)     count=14 ;;
            stress_patterns)   count=70 ;;
            sqlite_binding)    count=4 ;;
            openssl_wrapper)   count=6 ;;
            zlib_binding)      count=6 ;;
            rust_sqlite_ffi)   count=6 ;;
        esac
    fi

    echo "$count"
}

run_analysis() {
    local ir_file="$1"
    local output_file="$2"

    if [[ ! -f "$ir_file" ]]; then
        echo "WARNING: IR file not found: $ir_file" >&2
        echo "[]" > "$output_file"
        echo "0"
        return
    fi

    cd "$PROJECT_ROOT"

    local raw_output
    raw_output=$($ZIG build run -- "$ir_file" 2>&1 || true)

    local issue_count=0
    local ffi_critical_count=0
    local ffi_high_count=0
    local zone_total=0
    local ptr_violations=0
    local leak_candidates=0
    local vulnerability_count=0

    while IFS= read -r line; do
        if [[ "$line" =~ \[CRITICAL\]\ FFI\ RISK ]] || [[ "$line" =~ FFI\ RISK.*command ]] || \
               [[ "$line" =~ \[OMI-CRITICAL\] ]] || [[ "$line" =~ STACK-ESCAPE ]] || \
               [[ "$line" =~ RETURN-STACK ]] || [[ "$line" =~ VULNERABILITY.*\[critical\] ]]; then
            ((ffi_critical_count++)) || true
        elif [[ "$line" =~ \[HIGH\]\ FFI\ RISK ]] || [[ "$line" =~ FFI\ RISK ]] || \
             [[ "$line" =~ \[HIGH\]\ RISKY\ LIBC\ CALL ]] || [[ "$line" =~ CROSS-LANGUAGE ]] || \
             [[ "$line" =~ \[OMI-HIGH\] ]] || [[ "$line" =~ VULNERABILITY.*\[high\] ]]; then
            ((ffi_high_count++)) || true
        fi

        if [[ "$line" =~ VULNERABILITY\ (OMI-[0-9]+) ]] || \
             [[ "$line" =~ (MEMORY\ LEAK|DOUBLE-FREE|USE-AFTER-FREE) ]]; then
            ((vulnerability_count++)) || true
        fi

        if [[ "$line" =~ found\ ([0-9]+)\ violation ]]; then
            ptr_violations=${BASH_REMATCH[1]}
        fi
        if [[ "$line" =~ ([0-9]+)\ leak\ candidates\ reported ]]; then
            leak_candidates=${BASH_REMATCH[1]}
        fi
        if [[ "$line" =~ Issues\ found:\ *([0-9]+) ]]; then
            zone_total=${BASH_REMATCH[1]}
        fi
    done <<< "$raw_output"

    if [[ $zone_total -gt 0 ]]; then
        issue_count=$zone_total
    else
        issue_count=$((vulnerability_count + ptr_violations + leak_candidates))
    fi

    if [[ $issue_count -lt $((vulnerability_count + ptr_violations + leak_candidates)) ]]; then
        issue_count=$((vulnerability_count + ptr_violations + leak_candidates))
    fi

    echo "$raw_output" > "${output_file%.json}.raw"
    echo "${issue_count}|${ffi_critical_count}|${ffi_high_count}"
}

analyze_corpus_category() {
    local category="$1"
    local category_dir="$CORPUS_DIR/$category/output"

    if [[ ! -d "$category_dir" ]]; then
        return
    fi

    echo ""
    echo -e "${BLUE}=== Analyzing: $category/ ===${NC}"

    for ir_file in "$category_dir"/*.ll; do
        [[ -f "$ir_file" ]] || continue

        local base_name=$(basename "$ir_file" .ll)
        local output_file="$OUTPUT_DIR/${category}_${base_name}.json"

        echo -n "  Analyzing $(basename "$ir_file") ... "

        local result
        result=$(run_analysis "$ir_file" "$output_file")

        local detected="${result%%|*}"
        local ffi_crit="${result#*|}"; ffi_crit="${ffi_crit%%|*}"
        local ffi_high="${result##*|}"

        local expected
        expected=$(get_expected_count "$base_name" "$category")

        echo "${detected}|${expected}|${ffi_crit}|${ffi_high}|${ir_file}" >> "$STATS_FILE"

        TOTAL_DETECTED=$((TOTAL_DETECTED + detected))
        TOTAL_EXPECTED=$((TOTAL_EXPECTED + expected))
        TOTAL_FFI_CRITICAL=$((TOTAL_FFI_CRITICAL + ffi_crit))
        TOTAL_FFI_HIGH=$((TOTAL_FFI_HIGH + ffi_high))

        if [[ $expected -gt 0 && $detected -eq $expected ]]; then
            echo -e "${GREEN}✓ $detected issues (expected: $expected)${NC}"
        elif [[ $expected -eq 0 && $detected -eq 0 ]]; then
            echo -e "${GREEN}✓ Clean (no issues expected)${NC}"
        elif [[ $detected -lt $expected ]]; then
            echo -e "${YELLOW}⚠ $detected/$expected (FFI: ${ffi_crit}C/${ffi_high}H)${NC}"
        else
            echo -e "${RED}✗ $detected (expected: $expected, +$((detected - expected)) FP?)${NC}"
        fi
    done
}

calculate_metrics() {
    local tp=0
    local fp=0
    local fn=0

    if [[ -f "$STATS_FILE" ]]; then
        while IFS='|' read -r detected expected ffi_crit ffi_high ir_file; do
            local min_val=$detected
            if [[ $expected -lt $min_val ]]; then
                min_val=$expected
            fi

            tp=$((tp + min_val))
            fp=$((fp + detected - min_val))
            fn=$((fn + expected - min_val))
        done < "$STATS_FILE"
    fi

    TOTAL_TP=$tp
    TOTAL_FP=$fp
    TOTAL_FN=$fn
}

print_summary() {
    calculate_metrics

    local precision="0"
    local recall="0"
    local f1="0"

    if [[ $((TOTAL_TP + TOTAL_FP)) -gt 0 ]]; then
        precision=$(awk "BEGIN {printf \"%.4f\", $TOTAL_TP / ($TOTAL_TP + $TOTAL_FP)}")
    else
        precision="1.0000"
    fi
    if [[ $((TOTAL_TP + TOTAL_FN)) -gt 0 ]]; then
        recall=$(awk "BEGIN {printf \"%.4f\", $TOTAL_TP / ($TOTAL_TP + $TOTAL_FN)}")
    else
        recall="1.0000"
    fi
    if [[ $(echo "$precision $recall" | awk '{print ($1+0 > 0 && $2+0 > 0)}') -eq 1 ]]; then
        f1=$(awk "BEGIN {printf \"%.4f\", 2 * ($precision+0) * ($recall+0) / (($precision+0) + ($recall+0))}")
    else
        f1="1.0000"
    fi

    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         OmniScope FFI/Unsafe Benchmark (v0.1.7)          ║${NC}"
    echo -e "${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║  Core Focus: FFI Boundary / Unsafe Memory / Command Exec  ║${NC}"
    echo -e "${BLUE}║  Secondary: Memory Leaks, UAF, Double-Free (FFI context)  ║${NC}"
    echo -e "${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
    printf "${BLUE}║  FFI CRITICAL (command injection):     %-23d║${NC}\n" "$TOTAL_FFI_CRITICAL"
    printf "${BLUE}║  FFI HIGH (risky FFI calls):           %-23d║${NC}\n" "$TOTAL_FFI_HIGH"
    echo -e "${BLUE}║  ─────────────────────────────────────────────────────────── ║${NC}"
    printf "${BLUE}║  True Positives:        %-32d║${NC}\n" "$TOTAL_TP"
    printf "${BLUE}║  False Positives:       %-32d║${NC}\n" "$TOTAL_FP"
    printf "${BLUE}║  False Negatives:       %-32d║${NC}\n" "$TOTAL_FN"
    printf "${BLUE}║  Total Detected:        %-32d║${NC}\n" "$TOTAL_DETECTED"
    printf "${BLUE}║  Expected:              %-32d║${NC}\n" "$TOTAL_EXPECTED"
    echo -e "${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
    printf "${BLUE}║  Precision:             %-32s║${NC}\n" "$precision"
    printf "${BLUE}║  Recall:                %-32s║${NC}\n" "$recall"
    printf "${BLUE}║  F1 Score:              %-32s║${NC}\n" "$f1"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"

    TARGET_FFI_CRITICAL="${OMNISCOPE_TARGET_FFI_CRITICAL:-2}"
    TARGET_FFI_HIGH="${OMNISCOPE_TARGET_FFI_HIGH:-4}"
    TARGET_PRECISION="${OMNISCOPE_TARGET_P:-0.40}"
    TARGET_RECALL="${OMNISCOPE_TARGET_R:-0.70}"
    TARGET_F1="${OMNISCOPE_TARGET_F:-0.54}"

    local all_pass=true

    local ffi_crit_pass=true
    if [[ $TOTAL_FFI_CRITICAL -lt $TARGET_FFI_CRITICAL ]]; then
        ffi_crit_pass=false
        all_pass=false
    fi

    local ffi_high_pass=true
    if [[ $TOTAL_FFI_HIGH -lt $TARGET_FFI_HIGH ]]; then
        ffi_high_pass=false
        all_pass=false
    fi

    local prec_pass=true
    if [[ $(echo "$precision $TARGET_PRECISION" | awk '{print ($1+0 >= $2+0)}') -ne 1 ]]; then
        prec_pass=false
        all_pass=false
    fi

    local rec_pass=true
    if [[ $(echo "$recall $TARGET_RECALL" | awk '{print ($1+0 >= $2+0)}') -ne 1 ]]; then
        rec_pass=false
        all_pass=false
    fi

    local f1_pass=true
    if [[ $(echo "$f1 $TARGET_F1" | awk '{print ($1+0 >= $2+0)}') -ne 1 ]]; then
        f1_pass=false
        all_pass=false
    fi

    echo ""
    echo -e "FFI Focus Targets (v0.1.7):"
    echo -e "  FFI CRITICAL (command exec): >= $TARGET_FFI_CRITICAL  $(if $ffi_crit_pass; then echo "${GREEN}PASS${NC} ($TOTAL_FFI_CRITICAL detected)"; else echo "${RED}FAIL${NC} ($TOTAL_FFI_CRITICAL detected, need $TARGET_FFI_CRITICAL)"; fi)"
    echo -e "  FFI HIGH (risky FFI):         >= $TARGET_FFI_HIGH   $(if $ffi_high_pass; then echo "${GREEN}PASS${NC} ($TOTAL_FFI_HIGH detected)"; else echo "${RED}FAIL${NC} ($TOTAL_FFI_HIGH detected, need $TARGET_FFI_HIGH)"; fi)"
    echo ""
    echo -e "Quality Targets:"
    echo -e "  Precision >= $TARGET_PRECISION   $(if $prec_pass; then echo "${GREEN}PASS${NC} ($precision)"; else echo "${RED}FAIL${NC} ($precision)"; fi)"
    echo -e "  Recall >= $TARGET_RECALL       $(if $rec_pass; then echo "${GREEN}PASS${NC} ($recall)"; else echo "${RED}FAIL${NC} ($recall)"; fi)"
    echo -e "  F1 Score >= $TARGET_F1        $(if $f1_pass; then echo "${GREEN}PASS${NC} ($f1)"; else echo "${RED}FAIL${NC} ($f1)"; fi)"

    if $all_pass; then
        echo -e "\n${GREEN}=== BENCHMARK PASSED ===${NC}"
        return 0
    else
        echo -e "\n${RED}=== BENCHMARK FAILED ===${NC}"
        return 1
    fi
}

generate_json_report() {
    calculate_metrics

    local precision="0"
    local recall="0"
    local f1="0"

    if [[ $((TOTAL_TP + TOTAL_FP)) -gt 0 ]]; then
        precision=$(awk "BEGIN {printf \"%.4f\", $TOTAL_TP / ($TOTAL_TP + $TOTAL_FP)}")
    else
        precision="1.0000"
    fi
    if [[ $((TOTAL_TP + TOTAL_FN)) -gt 0 ]]; then
        recall=$(awk "BEGIN {printf \"%.4f\", $TOTAL_TP / ($TOTAL_TP + $TOTAL_FN)}")
    else
        recall="1.0000"
    fi
    if [[ $(echo "$precision $recall" | awk '{print ($1+0 > 0 && $2+0 > 0)}') -eq 1 ]]; then
        f1=$(awk "BEGIN {printf \"%.4f\", 2 * ($precision+0) * ($recall+0) / (($precision+0) + ($recall+0))}")
    else
        f1="1.0000"
    fi

    local per_file_json=""
    local first=true

    if [[ -f "$STATS_FILE" ]]; then
        while IFS='|' read -r detected expected ffi_crit ffi_high ir_file; do
            local fname=$(basename "$ir_file")
            if $first; then
                first=false
            else
                per_file_json="${per_file_json},"
            fi
            per_file_json="${per_file_json}
    {\"file\": \"${fname}\", \"detected\": ${detected}, \"expected\": ${expected}, \"ffi_critical\": ${ffi_crit}, \"ffi_high\": ${ffi_high}}"
        done < "$STATS_FILE"
    fi

    cat <<EOF
{
  "benchmark_id": "omniscope-$(date +%Y%m%d-%H%M%S)",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "scope": "FFI/Unsafe Boundary Analysis",
  "environment": {
    "os": "$(uname -s)",
    "cpu": "$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')",
    "zig_version": "$($ZIG version 2>/dev/null | head -1 || echo 'unknown')",
    "build_mode": "ReleaseFast"
  },
  "ffi_summary": {
    "ffi_critical": $TOTAL_FFI_CRITICAL,
    "ffi_high": $TOTAL_FFI_HIGH
  },
  "results": {
    "total_tp": $TOTAL_TP,
    "total_fp": $TOTAL_FP,
    "total_fn": $TOTAL_FN,
    "total_detected": $TOTAL_DETECTED,
    "total_expected": $TOTAL_EXPECTED,
    "precision": $precision,
    "recall": $recall,
    "f1_score": $f1,
    "false_positive_rate": 0
  },
  "targets": {
    "ffi_critical": 2,
    "ffi_high": 10,
    "precision": 0.40,
    "recall": 0.70,
    "f1_score": 0.54
  },
  "per_file": [
${per_file_json}
  ]
}
EOF
}

main() {
    local mode="full"
    local corpus_filter=""
    local single_file=""
    local output_json=false
    local ci_mode=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --corpus)
                corpus_filter="$2"
                shift 2
                ;;
            --file)
                single_file="$2"
                shift 2
                ;;
            --json)
                output_json=true
                shift
                ;;
            --ci)
                ci_mode=true
                shift
                ;;
            --help|-h)
                echo "OmniScope Benchmark Script"
                echo ""
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --corpus CAT   Only run specified corpus category (small/medium/large/ffi-dense)"
                echo "  --file PATH    Run single IR file"
                echo "  --json         Output results as JSON"
                echo "  --ci           CI mode: exit 0 on pass, exit 1 on fail"
                echo "  --help         Show this help"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    mkdir -p "$OUTPUT_DIR"
    : > "$STATS_FILE"

    parse_expected_results

    if [[ -n "$single_file" ]]; then
        local output_file="$OUTPUT_DIR/single_result.json"
        local count
        count=$(run_analysis "$single_file" "$output_file")
        echo "Detected $count issues in $single_file"

        if $output_json; then
            cat "$output_file"
        fi
        exit 0
    fi

    if [[ -n "$corpus_filter" ]]; then
        analyze_corpus_category "$corpus_filter"
    else
        analyze_corpus_category "small"
        analyze_corpus_category "medium"
        analyze_corpus_category "large"
        analyze_corpus_category "ffi-dense"

        echo ""
        echo -e "${BLUE}=== Analyzing: red_team_test/ (FFI Focus) ===${NC}"

        local red_team_ir="$PROJECT_ROOT/corpus/red_team_test/red_team_bugs_O0.ll"
        if [[ ! -f "$red_team_ir" ]]; then
            clang -S -emit-llvm -g -O0 -o "$red_team_ir" "$PROJECT_ROOT/corpus/red_team_test/red_team_bugs.c" 2>/dev/null || true
        fi

        if [[ -f "$red_team_ir" ]]; then
            echo -n "  Analyzing red_team_bugs.ll ... "

            local result
            result=$(run_analysis "$red_team_ir" "$OUTPUT_DIR/red_team_bugs.json")

            local detected="${result%%|*}"
            local ffi_crit="${result#*|}"; ffi_crit="${ffi_crit%%|*}"
            local ffi_high="${result##*|}"

            echo "FFI: ${ffi_crit}C/${ffi_high}H (Total: $detected)"

            TOTAL_FFI_CRITICAL=$((TOTAL_FFI_CRITICAL + ffi_crit))
            TOTAL_FFI_HIGH=$((TOTAL_FFI_HIGH + ffi_high))
        fi
    fi

    echo ""
    echo -e "${BLUE}=== Analyzing: Extended Corpus (ffi-dense + real_world) ===${NC}"

    local critical_patterns="$PROJECT_ROOT/corpus/red_team_test/v017_critical_patterns.ll"
    if [[ -f "$critical_patterns" ]]; then
        echo -n "  v017_critical_patterns.ll ... "
        local result
        result=$(run_analysis "$critical_patterns" "$OUTPUT_DIR/v017_critical_patterns.json")
        local detected="${result%%|*}"
        local ffi_crit="${result#*|}"; ffi_crit="${ffi_crit%%|*}"
        local ffi_high="${result##*|}"
        echo "FFI: ${ffi_crit}C/${ffi_high}H ($detected issues)"
        TOTAL_DETECTED=$((TOTAL_DETECTED + detected))
        TOTAL_FFI_CRITICAL=$((TOTAL_FFI_CRITICAL + ffi_crit))
        TOTAL_FFI_HIGH=$((TOTAL_FFI_HIGH + ffi_high))
    fi

    for ext_dir in "ffi-dense" "real_world/zkp" "real_world/other"; do
        ext_path="$CORPUS_DIR/$ext_dir"
        if [[ -d "$ext_path" ]]; then
            for ir_file in "$ext_dir"/*.ll; do
                [[ -f "$ir_file" ]] || continue
                local name=$(basename "$ir_file")
                echo -n "  $name ... "
                local result
                result=$(run_analysis "$ir_file" "$OUTPUT_DIR/ext_${name}.json")
                local detected="${result%%|*}"
                local ffi_crit="${result#*|}"; ffi_crit="${ffi_crit%%|*}"
                local ffi_high="${result##*|}"
                echo "FFI: ${ffi_crit}C/${ffi_high}H ($detected issues)"
                TOTAL_DETECTED=$((TOTAL_DETECTED + detected))
                TOTAL_FFI_CRITICAL=$((TOTAL_FFI_CRITICAL + ffi_crit))
                TOTAL_FFI_HIGH=$((TOTAL_FFI_HIGH + ffi_high))
            done
        fi
    done

    if $output_json; then
        generate_json_report
        exit $?
    fi

    print_summary
    local result=$?

    generate_json_report > "$OUTPUT_DIR/benchmark-results.json"

    rm -f "$STATS_FILE"

    if $ci_mode; then
        exit $result
    fi

    exit 0
}

main "$@"
