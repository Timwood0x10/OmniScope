#!/bin/bash
# OmniScope Performance Benchmark Suite
#
# Usage:
#   ./scripts/bench_perf.sh [all|blst|ring|wasmtime]
#   ./scripts/bench_perf.sh --compare
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
RESULTS_DIR="$PROJECT_ROOT/test_results/perf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[BENCH]${NC} $*"; }
log_pass() { echo -e "${GREEN}[OK]${NC} $*"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; }

ensure_build() {
    if [ ! -f "$BUILD_DIR/OmniScope" ]; then
        log_info "Building OmniScope..."
        cd "$PROJECT_ROOT" && make build
    fi
}

measure_time() {
    local cmd="$1"
    local output_file="$2"

    # Run 3 times and take median
    local times=()
    for i in 1 2 3; do
        local start_ns=$(date +%s%N)
        eval "$cmd" > /dev/null 2>&1 || true
        local end_ns=$(date +%s%N)
        local elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
        times+=($elapsed_ms)
    done

    # Sort and pick middle value
    sorted=($(for t in "${times[@]}"; do echo $t; done | sort -n))
    local median=${sorted[1]}
    
    echo "$median" > "$output_file"
    echo "$median"
}

get_memory_kb() {
    local pid="$1"
    if command -v ps >/dev/null 2>&1; then
        ps -o rss= -p "$pid" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

bench_blst() {
    log_info "Benchmarking blst..."
    local IR_FILE="$PROJECT_ROOT/test_ir/real/blst_sample.ll"
    local OUTPUT="/tmp/blst_bench_output.json"
    local TIME_RESULT="$RESULTS_DIR/blst_time.txt"
    local MEM_RESULT="$RESULTS_DIR/blst_mem.txt"

    mkdir -p "$RESULTS_DIR"

    if [ ! -f "$IR_FILE" ]; then
        log_fail "blst: IR file not found"
        return
    fi

    # Measure time
    local time_ms=$(measure_time "\"$BUILD_DIR/OmniScope\" analyze --input \"$IR_FILE\" --output \"$OUTPUT\"" "$TIME_RESULT")
    
    # Measure memory (approximate via /proc or similar)
    local mem_kb="N/A"

    log_pass "blst: ${time_ms}ms (target: <500ms)"
    
    # Check against target
    if [ "$time_ms" -le 500 ]; then
        log_pass "blst: Within target (<500ms)"
    else
        log_fail "blst: Exceeds target (${time_ms}ms > 500ms)"
    fi

    echo "{\"project\":\"blst\",\"time_ms\":$time_ms,\"target_ms\":500,\"memory_kb\":$mem_kb}" > "$RESULTS_DIR/blst_result.json"
}

bench_ring() {
    log_info "Benchmarking ring..."
    local IR_FILE="$PROJECT_ROOT/test_ir/real/ring_sample.ll"
    local OUTPUT="/tmp/ring_bench_output.json"
    local TIME_RESULT="$RESULTS_DIR/ring_time.txt"
    local MEM_RESULT="$RESULTS_DIR/ring_mem.txt"

    mkdir -p "$RESULTS_DIR"

    if [ ! -f "$IR_FILE" ]; then
        log_fail "ring: IR file not found"
        return
    fi

    local time_ms=$(measure_time "\"$BUILD_DIR/OmniScope\" analyze --input \"$IR_FILE\" --output \"$OUTPUT\"" "$TIME_RESULT")
    local mem_kb="N/A"

    log_pass "ring: ${time_ms}ms (target: <200ms)"
    
    if [ "$time_ms" -le 200 ]; then
        log_pass "ring: Within target (<200ms)"
    else
        log_fail "ring: Exceeds target (${time_ms}ms > 200ms)"
    fi

    echo "{\"project\":\"ring\",\"time_ms\":$time_ms,\"target_ms\":200,\"memory_kb\":$mem_kb}" > "$RESULTS_DIR/ring_result.json"
}

bench_wasmtime() {
    log_info "Benchmarking wasmtime..."
    local IR_FILE="$PROJECT_ROOT/test_ir/real/wasmtime_sample.ll"
    local OUTPUT="/tmp/wasmtime_bench_output.json"
    local TIME_RESULT="$RESULTS_DIR/wasmtime_time.txt"

    mkdir -p "$RESULTS_DIR"

    if [ ! -f "$IR_FILE" ]; then
        log_fail "wasmtime: IR file not found"
        return
    fi

    local time_ms=$(measure_time "\"$BUILD_DIR/OmniScope\" analyze --input \"$IR_FILE\" --output \"$OUTPUT\"" "$TIME_RESULT")

    log_pass "wasmtime: ${time_ms}ms (target: <1000ms)"
    
    if [ "$time_ms" -le 1000 ]; then
        log_pass "wasmtime: Within target (<1000ms)"
    else
        log_fail "wasmtime: Exceeds target (${time_ms}ms > 1000ms)"
    fi

    echo "{\"project\":\"wasmtime\",\"time_ms\":$time_ms,\"target_ms\":1000}" > "$RESULTS_DIR/wasmtime_result.json"
}

bench_compare() {
    log_info "Comparing with previous baseline..."
    
    local BASELINE_FILE="$PROJECT_ROOT/docs/investigation_reports/zh/perf_baseline.json"
    
    if [ ! -f "$BASELINE_FILE" ]; then
        log_info "No baseline found, creating initial baseline..."
        bench_all
        return
    fi
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              PERFORMANCE COMPARISON REPORT                  ║"
    echo "╠═══════════════╦════════════╦════════════╦══════════════════╣"
    echo "║ Project       ║ Baseline   ║ Current    ║ Change            ║"
    echo "╠═══════════════╬════════════╬════════════╬══════════════════╣"
    
    for project in blst ring wasmtime; do
        local result_file="$RESULTS_DIR/${project}_result.json"
        if [ -f "$result_file" ]; then
            local current=$(grep -o '"time_ms":[0-9]*' "$result_file" | cut -d: -f2)
            local baseline=$(jq -r ".${project}.time_ms // 0" "$BASELINE_FILE" 2>/dev/null || echo "0")
            
            if [ "$baseline" != "0" ] && [ "$current" != "" ]; then
                local change=$(( current - baseline ))
                local pct=$(( change * 100 / baseline ))
                
                if [ "$change" -lt 0 ]; then
                    printf "║ %-13s ║ %8sms ║ %8sms ║ ${GREEN}%+d%% faster${NC}   \n" \
                        "$project" "$baseline" "$current" "$pct"
                elif [ "$change" -gt 0 ]; then
                    printf "║ %-13s ║ %8sms ║ %8sms ║ ${RED}%+d%% slower${NC}   \n" \
                        "$project" "$baseline" "$current" "$pct"
                else
                    printf "║ %-13s ║ %8sms ║ %8sms ║ no change          \n" \
                        "$project" "$baseline" "$current"
                fi
            fi
        fi
    done
    
    echo "╚═══════════════╩════════════╩════════════╩══════════════════╝"
}

bench_all() {
    ensure_build
    mkdir -p "$RESULTS_DIR"
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           OmniScope v0.1.6 Performance Benchmarks             ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    bench_blst
    echo ""
    bench_ring
    echo ""
    bench_wasmtime
    echo ""
    
    # Generate summary JSON
    echo "{" > "$RESULTS_DIR/all_results.json"
    local first=true
    for project in blst ring wasmtime; do
        local f="$RESULTS_DIR/${project}_result.json"
        if [ -f "$f" ]; then
            if [ "$first" = true ]; then first=false; else echo "," >> "$RESULTS_DIR/all_results.json"; fi
            cat "$f" >> "$RESULTS_DIR/all_results.json"
        fi
    done
    echo "}" >> "$RESULTS_DIR/all_results.json"
}

print_summary() {
    echo ""
    echo "Results saved to: $RESULTS_DIR/"
    ls -la "$RESULTS_DIR/"*.json 2>/dev/null || true
}

main() {
    local target="${1:-all}"
    
    case "$target" in
        all) bench_all; print_summary ;;
        blst) ensure_build; bench_blst ;;
        ring) ensure_build; bench_ring ;;
        wasmtime) ensure_build; bench_wasmtime ;;
        compare) bench_compare ;;
        *)
            echo "Usage: $0 [all|blst|ring|wasmtime|compare]"
            exit 1
            ;;
    esac
}

main "$@"
