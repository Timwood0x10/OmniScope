#!/bin/bash
# OmniScope v0.1.7 Full Corpus Analysis
set -e

BINARY="./zig-out/bin/OmniScope"
OUTDIR="outputs/full_analysis_v017"
rm -rf "$OUTDIR" && mkdir -p "$OUTDIR"

echo "=== OmniScope v0.1.7 Full Corpus Analysis ==="
echo "Date: $(date -Iseconds)"
echo ""

TOTAL_ISSUES=0
TOTAL_FUNCS=0
TOTAL_FFI=0
TOTAL_CROSS=0
CRASH_COUNT=0
OK_COUNT=0

extract_field() {
  echo "$1" | grep -o "\"$2\":[0-9]*" | grep -o "[0-9]*"
}

extract_text() {
  echo "$1" | grep -o "$2 [0-9]*" | head -1 | grep -o "[0-9]*"
}

for ll in $(find corpus/ -name "*.ll" -type f | sort); do
  name=$(basename "$ll" .ll)
  category=$(echo "$ll" | sed 's|corpus/||;s|/.*||')
  start=$(date +%s%N)

  set +e
  out=$("$BINARY" "$ll" --json 2>&1)
  rc=$?
  set -e

  end=$(date +%s%N)
  ms=$(( (end - start) / 1000000 ))

  if [ $rc -ne 0 ]; then
    echo "$out" > "$OUTDIR/${name}.err.log"
    printf "[CRASH] %-12s %-35s time=%sms exit=%d\n" "$category" "$name" "$ms" "$rc"
    CRASH_COUNT=$((CRASH_COUNT+1))
  else
    echo "$out" > "$OUTDIR/${name}.json"

    funcs=$(extract_field "$out" "functions")
    issues=$(extract_field "$out" "issues")
    ffi=$(extract_text "$out" "found .* FFI")
    cross=$(extract_text "$out" "cross-language edges")
    facts=$(extract_text "$out" "Facts generated")

    funcs=${funcs:-0}
    issues=${issues:-0}
    ffi=${ffi:-0}
    cross=${cross:-0}
    facts=${facts:-0}

    printf "[%-12s] %-35s funcs=%-6s issues=%-4s facts=%-8s FFI=%-6s cross=%-6s %sms\n" \
      "$category" "$name" "$funcs" "$issues" "$facts" "$ffi" "$cross" "$ms"

    TOTAL_ISSUES=$((TOTAL_ISSUES + issues))
    TOTAL_FUNCS=$((TOTAL_FUNCS + funcs))
    TOTAL_FFI=$((TOTAL_FFI + ffi))
    TOTAL_CROSS=$((TOTAL_CROSS + cross))
    OK_COUNT=$((OK_COUNT+1))
  fi
done

echo ""
echo "========================================="
echo "  OmniScope v0.1.7 Full Analysis Summary"
echo "========================================="
printf "  Files analyzed OK:   %d / 39\n" $OK_COUNT
printf "  Files crashed:       %d / 39\n" $CRASH_COUNT
printf "  Total Functions:     %d\n" $TOTAL_FUNCS
printf "  Total Issues:        %d\n" $TOTAL_ISSUES
printf "  Total FFI Boundaries: %d\n" $TOTAL_FFI
printf "  Total Cross-Lang Edges: %d\n" $TOTAL_CROSS
echo ""
echo "Output: $OUTDIR/"
ls "$OUTDIR/*.json" 2>/dev/null | wc -l | xargs echo "JSON files:"
ls "$OUTDIR/*.err.log" 2>/dev/null | wc -l | xargs echo "Error logs:"
