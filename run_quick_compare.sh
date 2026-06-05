#!/bin/bash
# Quick comparison v2: baseline vs override (after user's new changes)
set -uo pipefail

OMNISCOPE="./zig-out/bin/OmniScope"

echo "=============================================="
echo " BASELINE vs OVERRIDE (v2 — after new changes)"
echo "=============================================="
printf "%-38s %5s %5s %6s  %s\n" "FILE" "BASE" "OVR" "DELTA" "NOTES"
printf "%-38s %5s %5s %6s\n" "--------------------------------------" "-----" "---" "-----"

get_ovr() {
  case "$1" in
    rust_ffi_bugs)          echo "--default-lang rust --lang-prefix _ZN=rust --lang __rust_alloc=rust" ;;
    rust_ffi_edge_cases)   echo "--default-lang rust --lang-prefix _ZN=rust" ;;
    sqlite3|abseil2024|wabt_wast2json|openssl_wrapper|boundary_test|red_team_cpp_ffi|xxhash|c_merkle_tree|bun_alloc|crc32fast|zstd-rs)
                            echo "--default-lang c" ;;
    mach_core_test|zgui_test|zig_video_test|zig_ffi_edge_cases)
                            echo "--default-lang zig --lang-prefix zig_=zig" ;;
    python_capi_edge_cases|python_cffi_bugs)
                            echo "--default-lang python --lang-prefix PyInit_=python --lang-prefix _Py=python" ;;
    go_tinygo_ffi_bugs|go_cgo_bugs|go-sqlite3)
                            echo "--default-lang go --lang-prefix go_=go --lang-prefix __go_=go" ;;
    java_jni_bugs|java_jni_edge_cases)
                            echo "--default-lang java --lang-prefix Java_=java --lang-prefix JNI_=java" ;;
    csharp_ffi_bugs|csharp_ffi_edge_cases)
                            echo "--default-lang csharp --lang-prefix _N=csharp" ;;
    red_team_swift_ffi)     echo "--default-lang swift --lang-prefix _TFN=swift" ;;
    red_team_triple_chain)  echo "--default-lang c --lang-prefix _ZN=rust --lang-prefix go_=go" ;;
    sqlite_binding|zlib_binding)
                            echo "--default-lang c" ;;
    ring|blst|gnark_test|libsodium_blake2b|libsodium_sign|zkcrypto_bls12_381|zkcrypto_ff|ark_ff)
                            echo "--default-lang rust --lang-prefix _ZN=rust" ;;
    *)                       echo "--default-lang c" ;;
  esac
}

TOTAL=0; IMPROVED=0; WORSENED=0; UNCHANGED=0; FAIL=0
TOTAL_FP_REDUCTION=0

for f in \
  ./corpus/red_team_test/rust_ffi_bugs.ll \
  ./corpus/red_team_test/rust_ffi_edge_cases.ll \
  ./corpus/real_world/other/sqlite3.ll \
  ./corpus/real_world/other/abseil2024.ll \
  ./corpus/real_world/other/wabt_wast2json.ll \
  ./corpus/real_world/other/openssl_wrapper.ll \
  ./corpus/medium/boundary_test.ll \
  ./corpus/test_cases/zig/mach_core_test.ll \
  ./corpus/test_cases/zig/zgui_test.ll \
  ./corpus/test_cases/zig/zig_video_test.ll \
  ./corpus/red_team_test/red_team_cpp_ffi.ll \
  ./corpus/red_team_test/python_cffi_bugs.ll \
  ./corpus/red_team_test/python_capi_edge_cases.ll \
  ./corpus/red_team_test/go_cgo_bugs.ll \
  ./corpus/red_team_test/java_jni_bugs.ll \
  ./corpus/red_team_test/java_jni_edge_cases.ll \
  ./corpus/red_team_test/csharp_ffi_bugs.ll \
  ./corpus/red_team_test/csharp_ffi_edge_cases.ll \
  ./corpus/red_team_test/red_team_swift_ffi.ll \
  ./corpus/red_team_test/swift_ffi_edge_cases.ll \
  ./corpus/red_team_test/red_team_triple_chain.ll \
  ./corpus/red_team_test/zig_ffi_edge_cases.ll \
  ./corpus/ffi-dense/sqlite_binding.ll \
  ./corpus/ffi-dense/openssl_wrapper.ll \
  ./corpus/ffi-dense/zlib_binding.ll \
  ./corpus/real_project_test/bun_alloc.ll \
  ./corpus/real_project_test/crc32fast.ll \
  ./corpus/real_project_test/xxhash.ll \
  ./corpus/real_project_test/zstd-rs.ll \
  ./corpus/real_world/zkp/ring.ll \
  ./corpus/real_world/zkp/blst.ll \
  ./corpus/real_world/zkp/gnark_test.ll; do

  [ -f "$f" ] || continue
  bn=$(basename "$f" .ll)
  TOTAL=$((TOTAL+1))

  base_out=$($OMNISCOPE "$f" 2>/dev/null)
  base_ec=$?
  if [ $base_ec -ne 0 ]; then
    printf "%-38s %5s\n" "$bn" "PARSE_FAIL"
    FAIL=$((FAIL+1))
    continue
  fi
  base_cnt=$(echo "$base_out" | grep -cE '\[CRITICAL\]|\[HIGH\]' || echo "0")

  ovr_args=$(get_ovr "$bn")
  ovr_out=$($OMNISCOPE $ovr_args "$f" 2>/dev/null)
  ovr_ec=$?
  if [ $ovr_ec -ne 0 ]; then
    printf "%-38s %5d %5s\n" "$bn" "$base_cnt" "OVR_FAIL"
    FAIL=$((FAIL+1))
    continue
  fi
  ovr_cnt=$(echo "$ovr_out" | grep -cE '\[CRITICAL\]|\[HIGH\]' || echo "0")

  delta=$((ovr_cnt - base_cnt))
  if [ $delta -lt 0 ]; then
    note="FP REDUCED"
    IMPROVED=$((IMPROVED+1))
    TOTAL_FP_REDUCTION=$((TOTAL_FP_REDUCTION - delta))
  elif [ $delta -gt 0 ]; then
    note="MORE FINDINGS"
    WORSENED=$((WORSENED+1))
  else
    note="="
    UNCHANGED=$((UNCHANGED+1))
  fi

  printf "%-38s %5d %5d %+6d  %s\n" "$bn" "$base_cnt" "$ovr_cnt" "$delta" "$note"
done

echo ""
echo "=============================================="
echo " SUMMARY: ${TOTAL} files | IMPROVED=${IMPROVED} WORSENED=${WORSENED} UNCHANGED=${UNCHANGED} FAIL=${FAIL}"
echo " Total FP reduced: ${TOTAL_FP_REDUCTION}"
echo "=============================================="
