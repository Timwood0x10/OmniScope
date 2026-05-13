#!/bin/bash
# ============================================================================
#  OmniScope v0.1.8 - Real-World FFI/Unsafe Audit
# ============================================================================
#  Scans corpus/real_world/**/*.ll for FFI boundary and unsafe memory issues.
#
#  Usage:
#    ./scripts/run_realworld.sh           # Full audit
#    ./scripts/run_realworld.sh <file.ll> # Single file
#    ./scripts/run_realworld.sh --clean   # Clean outputs
#
#  Output: outputs/realworld/
#    ├── <name>.json   # JSON analysis result
#    ├── <name>.log    # Debug log (stderr)
#    ├── _summary.txt  # Human-readable summary
#    └── _summary.json # Machine-readable summary
#
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/outputs/realworld"
BINARY="$PROJECT_ROOT/zig-out/bin/OmniScope"
LL_DIR="$PROJECT_ROOT/corpus/real_world"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
TOTAL=0
TOTAL_ISSUES=0
_RESULTS_TMP=""

log_info()  { echo -e "${BLUE}[AUDIT]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
log_fail()  { echo -e "${RED}[FAIL]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_step()  { echo -e "${CYAN}${BOLD}  ── $*${NC}"; }
sep()       { printf "${CYAN}%*s${NC}\n" 72 '' | tr ' ' '─'; }

find_ll_files() {
    local dir="${1:-}"
    if [ -n "$dir" ]; then
        find "$LL_DIR/$dir" -maxdepth 2 -name "*.ll" 2>/dev/null || true
    else
        find "$LL_DIR" -name "*.ll" 2>/dev/null || true
    fi
}

ensure_binary() {
    if [ ! -f "$BINARY" ]; then
        log_info "Building OmniScope..."
        (cd "$PROJECT_ROOT" && make build) || {
            log_fail "Build failed!"
            exit 1
        }
    fi
}

setup_output() {
    mkdir -p "$OUTPUT_DIR"
    _RESULTS_TMP="$(mktemp "${OUTPUT_DIR}/.results.XXXXXX")"
}

cleanup() {
    rm -rf "$OUTPUT_DIR"/*.json "$OUTPUT_DIR"/*.log "$OUTPUT_DIR"/_summary.* \
           "$OUTPUT_DIR"/.results.* 2>/dev/null || true
    log_info "Output directory cleaned"
}

analyze_file() {
    local ll_file="$1"
    local name
    name="$(basename "$ll_file")"
    name="${name%.*}"

    TOTAL=$((TOTAL + 1))
    local json_out="$OUTPUT_DIR/${name}.json"
    local log_out="$OUTPUT_DIR/${name}.log"

    if [ ! -f "$ll_file" ]; then
        log_warn "SKIP $name -> file not found"
        return
    fi

    log_step "Analyzing: $name ($(du -h "$ll_file" | cut -f1))"

    local exit_code=0
    local start_ms=$(date +%s%N 2>/dev/null || date +%s)

    "$BINARY" --json --debug -o "$json_out" "$ll_file" > /dev/null 2> "$log_out" || exit_code=$?

    local end_ms=$(date +%s%N 2>/dev/null || date +%s)
    local elapsed_ms=0
    if [ -n "$(date +%s%N 2>/dev/null)" ]; then
        elapsed_ms=$(( (end_ms - start_ms) / 1000000 ))
    else
        elapsed_ms=$(( (end_ms - start_ms) * 1000 ))
    fi

    local count=0
    local top_kinds=""
    if [ -s "$json_out" ]; then
        local parse_result
        parse_result=$(python3 -c "
import json, sys
try:
    with open('$json_out') as f:
        data = json.load(f)
    issues = data.get('issues', data.get('diagnostics', data.get('vulnerabilities', [])))
    kinds = {}
    for i in (issues or []):
        k = i.get('kind', i.get('type', '?'))
        kinds[k] = kinds.get(k, 0) + 1
    top = sorted(kinds.items(), key=lambda x:-x[1])[:3]
    print(f'{len(issues or [])}|{\" \".join(f\"{k}({v})\" for k,v in top)}')
except Exception:
    print('0|')
" 2>/dev/null || echo "0|")
        count="${parse_result%%|*}"
        top_kinds="${parse_result#*|}"
    fi

    if [ "$count" = "0" ] && [ -s "$log_out" ]; then
        local log_count
        log_count=$(grep -oE 'Issues? (found|detected):?\s*[0-9]+' "$log_out" 2>/dev/null \
            | grep -oE '[0-9]+$' | head -1 || echo "0")
        if [ -n "$log_count" ] && [ "$log_count" != "0" ]; then
            count="$log_count"
        fi
    fi

    TOTAL_ISSUES=$((TOTAL_ISSUES + count))
    echo "${name}|${count}|${top_kinds}" >> "$_RESULTS_TMP"

    if [ $exit_code -ne 0 ] && [ ! -s "$json_out" ]; then
        FAIL=$((FAIL + 1))
        log_fail "$name -> error (exit=$exit_code, ${elapsed_ms}ms)"
        return
    fi

    PASS=$((PASS + 1))

    local c_color="$GREEN"
    if [ "$count" -ge 10 ]; then
        c_color="$RED"
    elif [ "$count" -ge 3 ]; then
        c_color="$YELLOW"
    fi

    log_ok "$name -> ${c_color}${count} issues${NC} (${elapsed_ms}ms)"
}

generate_summary() {
    local ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local summary_file="$OUTPUT_DIR/_summary.txt"

    {
        sep
        echo "  ${BOLD}OmniScope v0.1.8 — Real-World FFI/Unsafe Audit${NC}"
        echo "  $ts"
        sep
        echo ""
        echo "  Binary: $BINARY"
        echo "  Source: $LL_DIR/"
        echo "  Output: $OUTPUT_DIR/"
        echo ""

        printf "  ╔══════════════════╦══════╦════════╦════════════════════╗\n"
        printf "  ║ Metric           ║ Count║        ║                    ║\n"
        printf "  ╠══════════════════╬══════╬════════╬════════════════════╣\n"
        printf "  ║ Files analyzed   ║ %4d ║        ║                    ║\n" "$TOTAL"
        printf "  ║ Passed           ║ %4d ║ ✅     ║                    ║\n" "$PASS"
        printf "  ║ Failed           ║ %4d ║ ❌     ║                    ║\n" "$FAIL"
        printf "  ║ Total Issues     ║ %4d ║ 🔍     ║                    ║\n" "$TOTAL_ISSUES"
        printf "  ╚══════════════════╩══════╩════════╩════════════════════╝\n"
        echo ""

        if [ $TOTAL_ISSUES -gt 0 ] && [ -s "$_RESULTS_TMP" ]; then
            echo "  ┌──────────────────────┬───────┬────────────────────────────────┐"
            echo "  │ Project              │ Issues│ Top Kinds                      │"
            echo "  ├──────────────────────┼───────┼────────────────────────────────┤"
            sort -t'|' -k2 -rn "$_RESULTS_TMP" | while IFS='|' read -r n c t; do
                local c_color="$GREEN"
                [ "$c" -ge 10 ] 2>/dev/null && c_color="$RED"
                [ "$c" -ge 3 ] 2>/dev/null && [ "$c" -lt 10 ] && c_color="$YELLOW"
                printf "  │ %-20s │ ${c_color}%5d${NC} │ %-30s │\n" "$n" "$c" "${t:0:30}"
            done
            echo "  └──────────────────────┴───────┴────────────────────────────────┘"
        fi

        echo ""
        echo "  FFI/Unsafe Categories Scanned:"
        echo "    • memory_leak          — malloc/calloc not freed"
        echo "    • use_after_free      — pointer used after free"
        echo "    • double_free         — double free detected"
        echo "    • null_dereference    — null pointer dereference"
        echo "    • uninitialized_use   — uninitialized memory read"
        echo "    • ffi_unsafe          — FFI boundary violations"
        echo "    • callback_escape     — C->Go/Rust callback escapes"
        echo "    • abi_mismatch        — ABI incompatibility"
        echo ""
        echo "  Output files:"
        echo "    *.json  -> Structured JSON results"
        echo "    *.log   -> Full debug logs with zone classification"
        echo ""
        sep

    } | tee "$summary_file"

    python3 -c "
import json, datetime
with open('$OUTPUT_DIR/_summary.json', 'w') as f:
    json.dump({
        'version': '0.1.8',
        'timestamp': datetime.datetime.utcnow().isoformat(),
        'total_files': $TOTAL,
        'passed': $PASS,
        'failed': $FAIL,
        'total_issues': $TOTAL_ISSUES,
        'output_dir': '$OUTPUT_DIR'
    }, f, indent=2)
" 2>/dev/null || true
}

main() {
    local target="${1:-all}"

    case "$target" in
        --clean|-c)
            setup_output
            cleanup
            exit 0
            ;;
        -h|--help)
            echo "Usage: $0 [options] [file...]"
            echo ""
            echo "Options:"
            echo "  --clean   Clean output directory"
            echo "  -h        Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                       # Audit all real_world .ll files"
            echo "  $0 sqlite3.ll            # Single file quick debug"
            exit 0
            ;;
    esac

    ensure_binary
    setup_output

    sep
    echo "  ${BOLD}OmniScope v0.1.8 — Real-World FFI/Unsafe Audit${NC}"
    echo "  Binary: $BINARY"
    echo "  Source: $LL_DIR/"
    echo "  Output: $OUTPUT_DIR/"
    sep
    echo ""

    local ll_files=()
    if [ "$target" = "all" ]; then
        while IFS= read -r f; do
            [ -n "$f" ] && ll_files+=("$f")
        done < <(find_ll_files)

        if [ ${#ll_files[@]} -eq 0 ]; then
            log_fail "No .ll files found in $LL_DIR/"
            exit 1
        fi

        log_info "Found ${#ll_files[@]} .ll file(s) to analyze"
        echo ""

        for ll_file in "${ll_files[@]}"; do
            analyze_file "$ll_file"
        done
    else
        for ll_file in "$@"; do
            analyze_file "$(cd "$LL_DIR" && find . -name "$ll_file" 2>/dev/null | head -1)"
        done
    fi

    echo ""
    generate_summary

    sep
    if [ $FAIL -eq 0 ]; then
        echo "  ${GREEN}${BOLD}✅ AUDIT COMPLETE — $PASS files, $TOTAL_ISSUES issues${NC}"
    else
        echo "  ${RED}${BOLD}⚠️  AUDIT COMPLETE — $PASS ok, $FAIL failed, $TOTAL_ISSUES issues${NC}"
    fi
    sep

    [ $FAIL -gt 0 ] && exit 1
    exit 0
}

main "$@"
