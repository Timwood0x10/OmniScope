#!/bin/bash
# OmniScope Real-World Analysis Script
# Usage: ./run_real_world_analysis.sh

set -e

OMNISCOPE_BIN="${OMNISCOPE_BIN:-./zig-out/bin/OmniScope}"
OUTPUT_DIR="./output"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

mkdir -p "$OUTPUT_DIR"

echo "=========================================="
echo " OmniScope Real-World Analysis"
echo " Binary: $OMNISCOPE_BIN"
echo " Scope:  ./corpus/real_world/**/*.ll"
echo " Output: $OUTPUT_DIR/"
echo "=========================================="
echo ""

total_files=0
total_issues=0
total_time=0

# Find all .ll files under corpus/real_world/ recursively
while IFS= read -r -d '' ll_file; do
    filename=$(basename "$ll_file")
    # Avoid name collisions: use relative path as prefix
    rel_path="${ll_file#./corpus/real_world/}"
    rel_prefix="${rel_path%.ll}"
    output_file="$OUTPUT_DIR/${rel_prefix}.txt"
    json_file="$OUTPUT_DIR/${rel_prefix}.json"

    # Create subdirectory if needed
    mkdir -p "$(dirname "$output_file")"

    total_files=$((total_files + 1))

    echo -e "${CYAN}[${total_files}] Analyzing: $ll_file${NC}"

    if [ -f "$OMNISCOPE_BIN" ]; then
        start_time=$(date +%s%N)

        # Text output
        "$OMNISCOPE_BIN" "$ll_file" > "$output_file" 2>&1 || true

        # JSON output if supported
        "$OMNISCOPE_BIN" --json "$ll_file" > "$json_file" 2>&1 || true

        end_time=$(date +%s%N)
        elapsed_ms=$(( (end_time - start_time) / 1000000 ))

        # Count issues
        issue_count=$(grep -c "^\[ERROR\]" "$output_file" 2>/dev/null || echo "0")
        warn_count=$(grep -c "^\[WARN\]" "$output_file" 2>/dev/null || echo "0")
        func_count=$(grep "Loaded:" "$output_file" 2>/dev/null | grep -oE "[0-9]+" || echo "?")

        total_issues=$((total_issues + issue_count))
        total_time=$((total_time + elapsed_ms))

        echo -e "  ${GREEN}✓${NC} Functions: $func_count | Issues: $issue_count | Warnings: $warn_count | Time: ${elapsed_ms}ms"
    else
        echo -e "  ${RED}✗ Binary not found: $OMNISCOPE_BIN${NC}"
    fi

    echo ""
done < <(find ./corpus/real_world/ -name "*.ll" -print0 | sort -z)

echo "=========================================="
echo " Summary"
echo "=========================================="
echo " Files analyzed: $total_files"
echo " Total issues:   $total_issues"
echo " Total time:     ${total_time}ms"
echo " Output dir:     $OUTPUT_DIR/"
echo "=========================================="
