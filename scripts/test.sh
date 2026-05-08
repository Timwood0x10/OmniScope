#!/bin/bash
# OmniScope Quick Test & Benchmark Script
# Usage: ./scripts/test.sh [quick|full|bench|smoke]
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

MODE="${1:-quick}"

case "$MODE" in
  quick)
    echo -e "${YELLOW}=== Quick Test (unit tests only) ===${NC}"
    zig build test 2>&1 | tail -5
    echo ""
    echo -e "${GREEN}✅ Quick test complete${NC}"
    ;;

  full)
    echo -e "${YELLOW}=== Full Test Suite ===${NC}"
    START=$(date +%s%N)
    RESULT=$(zig build test 2>&1)
    END=$(date +%s%N)
    ELAPSED=$(( (END - START) / 1000000 ))
    
    if echo "$RESULT" | grep -q "error:"; then
      echo -e "${RED}❌ Tests FAILED (${ELAPED}ms)${NC}"
      echo "$RESULT" | grep "failed:" | head -5
      exit 1
    else
      echo -e "${GREEN}✅ All tests PASSED (${ELAPED}ms)${NC}"
    fi
    ;;

  bench)
    echo -e "${YELLOW}=== Real Benchmark ===${NC}"
    if [ ! -f zig-out/bin/OmniScope ]; then
      echo "Building..."
      zig build
    fi

    echo ""
    echo "--- Red Team Tests ---"
    for f in corpus/red_team_test/*.ll; do
      if [ -f "$f" ]; then
        NAME=$(basename "$f" .ll)
        OUTPUT=$(./zig-out/bin/OmniScope "$f" --json 2>&1)
        ISSUES=$(echo "$OUTPUT" | grep "Issues found:" | awk '{print $NF}' | head -1)
        FUNCS=$(echo "$OUTPUT" | grep "Loaded:" | awk '{print $3}' | head -1)
        printf "  %-30s funcs=%-5s issues=%-3s\n" "$NAME" "${FUNCS:-0}" "${ISSUES:-0}"
      fi
    done

    echo ""
    echo "--- Real World ---"
    for f in corpus/real_world/other/sqlite3.ll corpus/real_world/other/curl8.ll corpus/real_world/zkp/ring.ll corpus/real_world/zkp/blst.ll; do
      if [ -f "$f" ]; then
        NAME=$(basename "$f" .ll)
        START=$(date +%s%N)
        OUTPUT=$(./zig-out/bin/OmniScope "$f" --json 2>&1)
        END=$(date +%s%N)
        ELAPSED=$(( (END - START) / 1000000 ))
        ISSUES=$(echo "$OUTPUT" | grep "Issues found:" | awk '{print $NF}' | head -1)
        FUNCS=$(echo "$OUTPUT" | grep "Loaded:" | awk '{print $3}' | head -1)
        printf "  %-30s funcs=%-5s issues=%-3s time=%dms\n" "$NAME" "${FUNCS:-0}" "${ISSUES:-0}" "$ELAPSED"
      fi
    done
    ;;

  smoke)
    echo -e "${YELLOW}=== Smoke Test (build + 1 file) ===${NC}"
    zig build || { echo -e "${RED}❌ Build failed${NC}"; exit 1; }
    echo -e "${GREEN}✅ Build OK${NC}"
    
    if [ -f corpus/red_team_test/subtle_unsafe_rs.ll ]; then
      OUTPUT=$(./zig-out/bin/OmniScope corpus/red_team_test/subtle_unsafe_rs.ll --json 2>&1)
      ISSUES=$(echo "$OUTPUT" | grep "Issues found:" | awk '{print $NF}' | head -1)
      echo "  subtle_unsafe_rs: ${ISSUES:-0} issues"
      echo -e "${GREEN}✅ Smoke test passed${NC}"
    else
      echo -e "${RED}❌ Test file not found${NC}"
      exit 1
    fi
    ;;

  *)
    echo "Usage: $0 [quick|full|bench|smoke]"
    echo "  quick  - Run unit tests only (default)"
    echo "  full   - Run full test suite with timing"
    echo "  bench  - Run real benchmark on all corpus files"
    echo "  smoke  - Build + single file analysis"
    exit 1
    ;;
esac
