#!/bin/zsh
set -eu

CORPUS_DIR="/Users/scc/code/zigcode/OmniScope/corpus"
TIMEOUT_SEC=60

# Cross-platform timeout: use gtimeout (GNU coreutils) on macOS if available,
# otherwise fall back to perl-based alarm wrapper.
TIMEOUT_CMD="timeout"
if [[ "$(uname)" == "Darwin" ]]; then
    if command -v gtimeout &>/dev/null; then
        TIMEOUT_CMD="gtimeout"
    else
        # Fallback: perl alarm wrapper for macOS without GNU coreutils
        TIMEOUT_CMD=""
    fi
fi

typeset -A FILE_ISSUES
typeset -A FILE_STATUS
typeset -A FILE_KINDS
typeset -A TOTAL_KINDS

TOTAL_FILES=0
TOTAL_OK=0
TOTAL_CRASH=0
TOTAL_TIMEOUT=0
TOTAL_OMI=0

extract_omi_count() {
    local raw="$1"
    local cnt
    cnt=$(echo "$raw" | grep -cE 'OMI-[0-9]+' 2>/dev/null) || true
    echo "${cnt:-0}"
}

extract_kinds() {
    local raw="$1"
    echo "$raw" | grep 'Type:' 2>/dev/null | sed 's/.*Type: *//' | sort | uniq -c | sort -rn || true
}

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    OmniScope Corpus Verification Report                     ║"
echo "║                    $(date '+%Y-%m-%d %H:%M:%S')                                    ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

FILES=($(find "$CORPUS_DIR" \( -name "*.ll" -o -name "*.bc" \) -type f | sort))
TOTAL_FILES=${#FILES[@]}

printf "Scanning %d files in %s ...\n\n" "$TOTAL_FILES" "$CORPUS_DIR"

idx=1
for file in "${FILES[@]}"; do
    name=$(basename "$file")
    rel_path="${file#$CORPUS_DIR/}"
    printf "[%2d/%d] Processing %-55s ..." "$idx" "$TOTAL_FILES" "$rel_path"

    if [[ -n "$TIMEOUT_CMD" ]]; then
        output=$("$TIMEOUT_CMD" "${TIMEOUT_SEC}" zig build run -- "$file" 2>&1)
        rc=$?
    else
        # Perl alarm fallback: run command with timeout
        output=$(perl -e 'alarm shift @ARGV; exec @ARGV' "${TIMEOUT_SEC}" zig build run -- "$file" 2>&1)
        rc=$?
    fi

    if [ $rc -eq 124 ]; then
        FILE_STATUS[$name]="TIMEOUT"
        FILE_ISSUES[$name]=0
        FILE_KINDS[$name]=""
        TOTAL_TIMEOUT=$((TOTAL_TIMEOUT + 1))
        printf "\r  [TIMEOUT] %-55s %3ds\n" "$rel_path" "$TIMEOUT_SEC"
    elif [ $rc -ne 0 ]; then
        FILE_STATUS[$name]="CRASH(exit:$rc)"
        FILE_ISSUES[$name]=0
        FILE_KINDS[$name]=""
        TOTAL_CRASH=$((TOTAL_CRASH + 1))
        printf "\r  [CRASH]  %-55s exit=%d\n" "$rel_path" "$rc"
    else
        omi_count=$(extract_omi_count "$output")
        omi_count=${omi_count:-0}
        [ -z "$omi_count" ] && omi_count=0
        kinds=$(extract_kinds "$output")

        FILE_STATUS[$name]="OK"
        FILE_ISSUES[$name]=$omi_count
        FILE_KINDS[$name]="$kinds"
        TOTAL_OK=$((TOTAL_OK + 1))
        TOTAL_OMI=$((TOTAL_OMI + omi_count))

        if [ "$omi_count" -gt 0 ]; then
            top_kind=$(echo "$kinds" | head -1 | awk '{$1=""; print $0}' | xargs 2>/dev/null || echo "-")
            printf "\r  [OK]     %-55s OMI=%-5d top: %s\n" "$rel_path" "$omi_count" "$top_kind"
        else
            printf "\r  [OK]     %-55s OMI=%-5d\n" "$rel_path" "$omi_count"
        fi

        while IFS= read -r line; do
            [ -z "$line" ] && continue
            count=$(echo "$line" | awk '{print $1}')
            kind=$(echo "$line" | awk '{$1=""; print $0}' | xargs 2>/dev/null || continue)
            if [ -n "$kind" ]; then
                if [ -z "${TOTAL_KINDS[$kind]:-}" ]; then
                    TOTAL_KINDS[$kind]=$count
                else
                    TOTAL_KINDS[$kind]=$((${TOTAL_KINDS[$kind]} + count))
                fi
            fi
        done <<< "$kinds"
    fi
    idx=$((idx + 1))
done

echo ""
echo "┌──────────────────────────────────────────────────────────────────────────────┐"
echo "│                              Summary                                         │"
echo "├──────────────────────────────────────────────────────────────────────────────┤"
printf "│  Total Files:      %-6d                                                       │\n" "$TOTAL_FILES"
printf "│  Analyzed OK:      %-6d  ✅                                                    │\n" "$TOTAL_OK"
printf "│  Crashed:          %-6d  ❌                                                    │\n" "$TOTAL_CRASH"
printf "│  Timeout:          %-6d  ⏱️                                                     │\n" "$TOTAL_TIMEOUT"
printf "│  Total OMI Issues: %-6d                                                       │\n" "$TOTAL_OMI"
echo "└──────────────────────────────────────────────────────────────────────────────┘"

if [ ${#TOTAL_KINDS} -gt 0 ]; then
    echo ""
    echo "┌─────────────────────────────┬───────┐"
    echo "│ Issue Type                  │ Count │"
    echo "├─────────────────────────────┼───────┤"

    for kind in ${(k)TOTAL_KINDS}; do
        count=${TOTAL_KINDS[$kind]}
        printf "│ %-27s │ %5d │\n" "$kind" "$count"
    done | sort -t'|' -k2 -rn

    echo "└─────────────────────────────┴───────┘"
fi

echo ""
echo "┌──────────────────────────────────────────────────────────────────────────────────────────┐"
echo "│ Per-File Details                                                                         │"
echo "├────────────────────────────────────────────────────┬───────┬──────────┬──────────────────┤"
echo "│ File                                                │ OMI   │ Status   │ Top Kinds        │"
echo "├────────────────────────────────────────────────────┼───────┼──────────┼──────────────────┤"

for file in "${FILES[@]}"; do
    name=$(basename "$file")
    rel_path="${file#$CORPUS_DIR/}"
    status="${FILE_STATUS[$name]}"
    issues="${FILE_ISSUES[$name]}"

    display_name="$rel_path"
    if [ ${#display_name} -gt 52 ]; then
        display_name="...${display_name: -49}"
    fi

    if [ "$status" = "OK" ] && [ "$issues" -gt 0 ]; then
        top_kinds=$(echo "${FILE_KINDS[$name]}" | head -3 | awk '{printf "%s(%s) ", $2, $1}' | sed 's/ $//')
        printf "│ %-52s │ %5d │ %-8s │ %-16s │\n" "$display_name" "$issues" "$status" "$top_kinds"
    elif [ "$status" = "OK" ]; then
        printf "│ %-52s │ %5d │ %-8s │ %-16s │\n" "$display_name" "$issues" "$status" "-"
    else
        printf "│ %-52s │ %5s │ %-8s │ %-16s │\n" "$display_name" "-" "$status" "-"
    fi
done

echo "└────────────────────────────────────────────────────┴───────┴──────────┴──────────────────┘"
echo ""
echo "Done."
