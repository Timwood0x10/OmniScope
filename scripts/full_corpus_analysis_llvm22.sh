#!/bin/bash
# OmniScope v0.1.7 Full Corpus Analysis with LLVM 22 (Robust Version)
set +e

BINARY="./zig-out/bin/OmniScope"
OUTDIR="outputs/full_analysis_v017_llvm22"
rm -rf "$OUTDIR" && mkdir -p "$OUTDIR"

# LLVM 22 tools
LLVM22_AS="/opt/homebrew/opt/llvm@22/bin/llvm-as"

echo "=== OmniScope v0.1.7 Full Corpus Analysis (LLVM 22) ==="
echo "Date: $(date -Iseconds)"
echo "LLVM Version: $($LLVM22_AS --version | head -1)"
echo ""

TOTAL_ISSUES=0
TOTAL_FUNCS=0
TOTAL_FFI=0
TOTAL_CROSS=0
CRASH_COUNT=0
OK_COUNT=0
CONV_FAIL=0
TOTAL_FILES=0

extract_field() {
  echo "$1" | grep -o "\"$2\":[0-9]*" | grep -o "[0-9]*"
}

extract_text() {
  echo "$1" | grep -o "$2 [0-9]*" | head -1 | grep -o "[0-9]*"
}

# Get all .ll files
FILES=$(find corpus/ -name "*.ll" -type f | sort)
TOTAL_FILES=$(echo "$FILES" | wc -l | tr -d ' ')

echo "Found $TOTAL_FILES .ll files to analyze"
echo ""

for ll in $FILES; do
  name=$(basename "$ll" .ll)
  category=$(echo "$ll" | sed 's|corpus/||;s|/.*||')
  
  # Try to convert with LLVM 22 first
  bcfile="/tmp/${name}.bc"
  $LLVM22_AS "$ll" -o "$bcfile" 2>/dev/null
  
  if [ ! -f "$bcfile" ] || [ $(wc -c < "$bcfile" 2>/dev/null || echo 0) -lt 100 ]; then
    printf "[CONV-FAIL] %-12s %-35s\n" "$category" "$name"
    CONV_FAIL=$((CONV_FAIL+1))
    rm -f "$bcfile"
    continue
  fi
  
  start=$(date +%s%N)

  # Analyze the converted .bc file
  out=$("$BINARY" "$bcfile" --json 2>&1)
  rc=$?

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

    funcs=${funcs:-0}
    issues=${issues:-0}
    ffi=${ffi:-0}
    cross=${cross:-0}

    printf "[OK] %-12s %-35s funcs=%-6s issues=%-4s FFI=%-6s cross=%-6s %sms\n" \
      "$category" "$name" "$funcs" "$issues" "$ffi" "$cross" "$ms"

    TOTAL_ISSUES=$((TOTAL_ISSUES + issues))
    TOTAL_FUNCS=$((TOTAL_FUNCS + funcs))
    TOTAL_FFI=$((TOTAL_FFI + ffi))
    TOTAL_CROSS=$((TOTAL_CROSS + cross))
    OK_COUNT=$((OK_COUNT+1))
  fi
  
  rm -f "$bcfile"
done

echo ""
echo "========================================="
echo "  OmniScope v0.1.7 Analysis Summary (LLVM 22)"
echo "========================================="
printf "  Total .ll files:     %d\n" $TOTAL_FILES
printf "  Conversion failures: %d\n" $CONV_FAIL
printf "  Files analyzed OK:   %d\n" $OK_COUNT
printf "  Files crashed:       %d\n" $CRASH_COUNT
printf "  Total Functions:     %d\n" $TOTAL_FUNCS
printf "  Total Issues:        %d\n" $TOTAL_ISSUES
printf "  Total FFI Boundaries: %d\n" $TOTAL_FFI
printf "  Total Cross-Lang Edges: %d\n" $TOTAL_CROSS
echo ""
echo "Output directory: $OUTDIR/"
echo "JSON result files:"
ls "$OUTDIR/*.json" 2>/dev/null | wc -l
echo "Error log files:"
ls "$OUTDIR/*.err.log" 2>/dev/null | wc -l
