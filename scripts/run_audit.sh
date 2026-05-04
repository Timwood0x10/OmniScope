#!/bin/bash
# ============================================================================
#  OmniScope v0.1.6 - Unified FFI/Unsafe Audit Runner
# ============================================================================
#  Usage:
#    ./scripts/run_audit.sh               # Full audit (auto-builds corpus)
#    ./scripts/run_audit.sh <file.ll>      # Single file quick debug
#    ./scripts/run_audit.sh --clean        # Clean outputs
#    ./scripts/run_audit.sh --build-only   # Only build corpus, no analysis
#
#  Output: outputs/audit/
#    ├── <name>.json      # JSON analysis result per file
#    ├── <name>.log       # Full debug log per file (stderr)
#    └── _summary.txt     # Human-readable summary
#
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/outputs/audit"
BINARY="$PROJECT_ROOT/zig-out/bin/OmniScope"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0
TOTAL=0
TOTAL_ISSUES=0

declare -a FILE_LIST=()
_RESULTS_TMP=""

log_info()  { echo -e "${BLUE}[AUDIT]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
log_fail()  { echo -e "${RED}[FAIL]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_step()  { echo -e "${CYAN}${BOLD}  ── $*${NC}"; }
separator() { printf "${CYAN}%*s${NC}\n" 72 '' | tr ' ' '─'; }

ensure_build() {
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

discover_files() {
    FILE_LIST=()
    local patterns=(
        "$PROJECT_ROOT/corpus/small/output/*.ll"
        "$PROJECT_ROOT/corpus/medium/output/*.ll"
        "$PROJECT_ROOT/corpus/large/output/*.ll"
        "$PROJECT_ROOT/corpus/ffi-dense/output/*.ll"
        "$PROJECT_ROOT/corpus/red_team_test/*.ll"
        "$PROJECT_ROOT/examples/"*/target/combined.bc
    )
    for pat in "${patterns[@]}"; do
        for f in $pat; do
            [ -f "$f" ] && FILE_LIST+=("$f")
        done
    done
    [ ${#FILE_LIST[@]} -eq 0 ] && return 1
    return 0
}

ensure_corpus() {
    if ! discover_files; then
        log_info "No IR files found. Building corpus..."
        (cd "$PROJECT_ROOT" && make corpus) || {
            log_warn "Corpus build partially failed, proceeding with available files"
        }
        discover_files || true
    fi
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
        SKIP=$((SKIP + 1))
        log_warn "SKIP $name -> file not found"
        return
    fi

    log_step "Analyzing: $name ($(basename $(dirname "$ll_file"))/$(basename "$ll_file"))"

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
    top = sorted(kinds.items(), key=lambda x:-x[1])[:2]
    print(f'{len(issues or [])}|{\" \".join(f\"{k}({v})\" for k,v in top)}')
except Exception:
    print('0|')
" 2>/dev/null || echo "0|")
        count="${parse_result%%|*}"
        top_kinds="${parse_result#*|}"
    fi

    if [ "$count" = "0" ] && [ -s "$log_out" ]; then
        local log_count
        log_count=$(grep -oE 'Issues? (found|detected):?\s*[0-9]+' "$log_out" 2>/dev/null | grep -oE '[0-9]+$' | head -1 || echo "0")
        if [ "$log_count" != "0" ] && [ -n "$log_count" ]; then
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

    local count_color="$GREEN"
    if [ "$count" -ge 5 ] 2>/dev/null; then count_color="$RED"
    elif [ "$count" -ge 1 ] 2>/dev/null; then count_color="$YELLOW"; fi

    log_ok   "$name -> ${count_color}${count} issues${NC} (${elapsed_ms}ms)"
    echo "  JSON: $json_out"
    echo "  LOG:  $log_out"
}

generate_summary() {
    local summary_file="$OUTPUT_DIR/_summary.txt"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    {
        separator
        echo "  ${BOLD}OmniScope v0.1.6 - FFI/Unsafe Boundary Security Audit${NC}"
        echo "  Generated: $timestamp"
        separator
        echo ""
        echo "  Binary : $BINARY"
        echo "  Output : $OUTPUT_DIR/"
        echo ""
        printf "  ╔═════════════════╦════════╦════════════════╗\n"
        printf "  ║ Metric          ║ Count  ║ Status          ║\n"
        printf "  ╠═════════════════╬════════╬══════════════════╣\n"
        printf "  ║ Files analyzed  ║ %5d   ║                  ║\n" "$TOTAL"
        printf "  ║ Passed          ║ %5d   ║ ✅              ║\n" "$PASS"
        printf "  ║ Failed          ║ %5d   ║ ❌              ║\n" "$FAIL"
        printf "  ║ Skipped         ║ %5d   ⏭️  ║\n" "$SKIP"
        printf "  ║ Total Issues    ║ %5d   ║ 🔍              ║\n" "$TOTAL_ISSUES"
        printf "  ╚═════════════════╩════════╩══════════════════╝\n"
        echo ""

        if [ $TOTAL_ISSUES -gt 0 ] && [ -s "$_RESULTS_TMP" ]; then
            echo "  ┌──────────────────────────────┬───────┬──────────────────────┐"
            echo "  │ File                        │ Issues│ Top Kinds            │"
            echo "  ├──────────────────────────────┼───────┼──────────────────────┤"
            sort -t'|' -k2 -rn "$_RESULTS_TMP" | while IFS='|' read -r n c t; do
                local c_color="$GREEN"
                [ "$c" -ge 5 ] 2>/dev/null && c_color="$RED"
                [ "$c" -ge 1 ] 2>/dev/null && [ "$c" -lt 5 ] && c_color="$YELLOW"
                printf "  │ %-26s │ ${c_color}%5d${NC} │ %-20s  │\n" "$n" "$c" "${t:0:20}"
            done
            echo "  └──────────────────────────────┴───────┴──────────────────────┘"
        fi

        echo ""
        echo "  Output files:"
        echo "    *.json  -> Structured JSON results"
        echo "    *.log   -> Debug logs with zone classification"
        echo ""
        separator

    } | tee "$summary_file"

    python3 -c "
import json, datetime
with open('$OUTPUT_DIR/_summary.json', 'w') as f:
    json.dump({
        'version': '0.1.6',
        'timestamp': datetime.datetime.utcnow().isoformat(),
        'total_files': $TOTAL,
        'passed': $PASS,
        'failed': $FAIL,
        'skipped': $SKIP,
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
        --build-only)
            ensure_build
            (cd "$PROJECT_ROOT" && make corpus)
            log_info "Corpus build complete. Files:"
            discover_files && for f in "${FILE_LIST[@]}"; do echo "  $f"; done
            exit 0
            ;;
        -h|--help)
            echo "Usage: $0 [options] [file...]"
            echo ""
            echo "Options:"
            echo "  --clean        Clean output directory"
            echo "  --build-only   Only build corpus IR files"
            echo "  -h, --help     Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                      # Audit all corpus files"
            echo "  $0 path/to/test.ll      # Quick single-file debug"
            exit 0
            ;;
    esac

    ensure_build
    setup_output

    separator
    echo "  ${BOLD}OmniScope v0.1.6 - FFI/Unsafe Boundary Security Audit${NC}"
    echo "  Binary : $BINARY"
    echo "  Output : $OUTPUT_DIR/"
    separator
    echo ""

    if [ "$target" = "all" ]; then
        ensure_corpus

        if [ ${#FILE_LIST[@]} -eq 0 ]; then
            log_fail "No IR files found! Run '$0 --build-only' first, or provide explicit paths."
            exit 1
        fi

        log_info "Found ${#FILE_LIST[@]} IR file(s) to analyze"
        echo ""

        for ll_file in "${FILE_LIST[@]}"; do
            analyze_file "$ll_file"
            echo ""
        done
    else
        for ll_file in "$@"; do
            analyze_file "$ll_file"
            echo ""
        done
    fi

    echo ""
    generate_summary

    separator
    if [ $FAIL -eq 0 ]; then
        echo "  ${GREEN}${BOLD}✅ AUDIT COMPLETE — $PASS passed, $TOTAL_ISSUES issues found${NC}"
    else
        echo "  ${RED}${BOLD}⚠️  AUDIT COMPLETE — $PASS passed, $FAIL failed, $TOTAL_ISSUES issues${NC}"
    fi
    separator

    [ $FAIL -gt 0 ] && exit 1
    exit 0
}

main "$@"
