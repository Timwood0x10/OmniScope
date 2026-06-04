#!/bin/bash
# ============================================================================
# OmniScope 全量基线测试 + Override 对比测试脚本 v3 (稳健版)
# ============================================================================
set -uo pipefail

OMNISCOPE="./zig-out/bin/OmniScope"
TIMEOUT_SEC=60
RESULTS_DIR="./test_results"
# External test fixture directory (override with EXTERNAL_FIXTURES env var)
EXTERNAL_FIXTURES="${EXTERNAL_FIXTURES:-./corpus/external}"
BASELINE_DIR="${RESULTS_DIR}/baseline"
OVERRIDE_DIR="${RESULTS_DIR}/override"

mkdir -p "$BASELINE_DIR" "$OVERRIDE_DIR"

# ─── 所有测试文件列表 ───
declare -a ALL_FILES=(
  "${EXTERNAL_FIXTURES}/cpp_hash.ll"
  "${EXTERNAL_FIXTURES}/cpp_fft.ll"
  "${EXTERNAL_FIXTURES}/c_hash_c_bridge.ll"
  "${EXTERNAL_FIXTURES}/c_fft_c_bridge.ll"
  "${EXTERNAL_FIXTURES}/c_ffi_traps.ll"
  "${EXTERNAL_FIXTURES}/c_merkle_tree.ll"
  "${EXTERNAL_FIXTURES}/rust_hash.ll"
  "${EXTERNAL_FIXTURES}/rust_merkle.ll"
  "${EXTERNAL_FIXTURES}/zig_ffi_bridge.ll"
  "${EXTERNAL_FIXTURES}/zig_main.ll"
  "./corpus/red_team_test/rust_ffi_bugs.ll"
  "./corpus/red_team_test/go_tinygo_ffi_bugs.ll"
  "./corpus/red_team_test/go_cgo_bugs.ll"
  "./corpus/red_team_test/java_jni_edge_cases.ll"
  "./corpus/red_team_test/zig_ffi_edge_cases.ll"
  "./corpus/red_team_test/swift_ffi_edge_cases.ll"
  "./corpus/red_team_test/csharp_ffi_edge_cases.ll"
  "./corpus/red_team_test/python_capi_edge_cases.ll"
  "./corpus/red_team_test/rust_ffi_edge_cases.ll"
  "./corpus/red_team_test/csharp_ffi_bugs.ll"
  "./corpus/red_team_test/python_cffi_bugs.ll"
  "./corpus/red_team_test/java_jni_bugs.ll"
  "./corpus/red_team_test/red_team_cpp_ffi.ll"
  "./corpus/red_team_test/red_team_triple_chain.ll"
  "./corpus/red_team_test/red_team_swift_ffi.ll"
  "./corpus/red_team_test/cross_lang_free_bugs.ll"
  "./corpus/real_project_test/bun_alloc.ll"
  "./corpus/real_project_test/zstd-rs.ll"
  "./corpus/real_project_test/xxhash.ll"
  "./corpus/real_project_test/go-sqlite3.ll"
  "./corpus/real_project_test/crc32fast.ll"
  "./corpus/real_world/other/rust_sqlite.ll"
  "./corpus/real_world/other/abseil2024.ll"
  "./corpus/real_world/zkp/ring.ll"
  "./corpus/real_world/zkp/gnark_test.ll"
  "./corpus/real_world/zkp/libsodium_blake2b.ll"
  "./corpus/real_world/zkp/libsodium_sign.ll"
  "./corpus/real_world/zkp/zkcrypto_bls12_381.ll"
  "./corpus/real_world/zkp/zkcrypto_ff.ll"
  "./corpus/real_world/zkp/ark_ff.ll"
  "./corpus/real_world/zkp/blst.ll"
  "./corpus/real_world/other/sqlite3.ll"
  "./corpus/real_world/other/wabt_wast2json.ll"
  "./corpus/real_world/other/openssl_wrapper.ll"
  "./corpus/real_world/other/ripgrep141.ll"
  "./corpus/medium/boundary_test.ll"
  "./corpus/ffi-dense/sqlite_binding.ll"
  "./corpus/ffi-dense/openssl_wrapper.ll"
  "./corpus/ffi-dense/zlib_binding.ll"
  "./corpus/test_cases/zig/mach_core_test.ll"
  "./corpus/test_cases/zig/zgui_test.ll"
  "./corpus/test_cases/zig/zig_video_test.ll"
)

TOTAL=${#ALL_FILES[@]}
echo "=============================================="
echo " OmniScope 全量测试 v3: 共 ${TOTAL} 个文件"
echo "=============================================="

# Filter out non-existent fixture files (graceful degradation)
declare -a EXISTING_FILES=()
for F in "${ALL_FILES[@]}"; do
  if [ -f "$F" ]; then
    EXISTING_FILES+=("$F")
  else
    echo "[WARN] Fixture not found: $F (skipping)"
  fi
done
ALL_FILES=("${EXISTING_FILES[@]}")
TOTAL=${#ALL_FILES[@]}
if [ "$TOTAL" -eq 0 ]; then
  echo "ERROR: No test fixtures found. Set EXTERNAL_FIXTURES=/path/to/fixtures"
  exit 1
fi

# get_override_args: 为不同测试文件生成 --lang / --default-lang 等覆盖参数。
# 注意：--source-lang 在此函数中用于覆盖解析路径的测试覆盖率，
# 尽管 lookupSourceFile() 与各 pass 的端到端集成尚待完成（参见 bugs.md #5）。
get_override_args() {
  local bn="$1"
  case "$bn" in
    cpp_hash|cpp_fft|c_hash_c_bridge|c_fft_c_bridge|c_ffi_traps|c_merkle_tree| \
    sqlite3|abseil2024|wabt_wast2json|openssl_wrapper|ripgrep141| \
    sqlite_binding|zlib_binding|boundary_test| \
    red_team_cpp_ffi|cross_lang_free_bugs|xxhash|bun_alloc)
      printf "%s" "--default-lang c"; return ;;
    rust_hash|rust_merkle|rust_sqlite|rust_ffi_bugs|rust_ffi_edge_cases| \
    zstd_rs|crc32fast|ring|gnark_test|libsodium_blake2b|libsodium_sign| \
    zkcrypto_bls12_381|zkcrypto_ff|ark_ff|blst)
      printf '%s' '--lang-prefix _ZN=rust --lang __rust_alloc=rust --lang __rust_dealloc=rust'; return ;;
    go_tinygo_ffi_bugs|go_cgo_bugs|go_sqlite3)
      printf "%s" "--lang-prefix go_=go --lang-prefix __go_=go"; return ;;
    zig_ffi_bridge|zig_main|zig_ffi_edge_cases|mach_core_test|zgui_test|zig_video_test)
      printf "%s" "--default-lang zig --lang-prefix zig_=zig"; return ;;
    swift_ffi_edge_cases|red_team_swift_ffi)
      printf "%s" "--lang-prefix _TFN=swift --default-lang swift"; return ;;
    csharp_ffi_edge_cases|csharp_ffi_bugs)
      printf "%s" "--lang-prefix _N=csharp --default-lang csharp"; return ;;
    python_capi_edge_cases|python_cffi_bugs)
      printf "%s" "--lang-prefix PyInit_=python --lang-prefix _Py=python --default-lang python --source-lang python_wrapper.py:python"; return ;;
    java_jni_edge_cases|java_jni_bugs)
      printf "%s" "--lang-prefix Java_=java --lang-prefix JNI_=java --default-lang java"; return ;;
    red_team_triple_chain)
      printf "%s" "--default-lang c --lang-prefix _ZN=rust --lang-prefix go_=go"; return ;;
    *) printf "%s" "--default-lang c"; return ;;
  esac
}

# 安全计数：grep 匹配数，无匹配返回 0
safe_grep_count() {
  local flag="" pattern="$1" file="$2"
  if [ "$pattern" = "-i" ]; then flag="-i"; pattern="$2"; file="$3"; fi
  grep -c${flag:+ $flag}E "$pattern" "$file" 2>/dev/null || true
}

# 运行单次测试
run_test() {
  local file="$1" out="$2" log="$3" args="${4:-}"
  local start=$(date +%s)
  if [ -n "$args" ]; then
    timeout "${TIMEOUT_SEC}" $OMNISCOPE $args "$file" > "$out" 2>"$log"
  else
    timeout "${TIMEOUT_SEC}" "$OMNISCOPE" "$file" > "$out" 2>"$log"
  fi
  local ec=$?
  local end=$(date +%s)
  printf '%s\n%s' "$ec" "$(( (end - start) * 1000 ))" > "${out}.meta"
  return $ec
}

# 提取指标，直接写到 CSV 行
extract_and_print() {
  local out="$1" csv="$2" extra_col="${3:-}"
  local bn=$(basename "$out" .txt)

  # 检查解析失败
  if grep -q "ModuleParseFailed\|FATAL.*could not parse\|error: could not open" "$out" 2>/dev/null; then
    local ms=$(awk 'NR==2' "${out}.meta" 2>/dev/null || echo "0")
    printf '%s\n' "${bn},PARSE_FAIL,${ms},0,0,0,0,0,0${extra_col}" >> "$csv"
    echo "PARSE_FAIL"
    return 1
  fi

  # 安全计数
  local crit=$(safe_grep_count '\[CRITICAL\]' "$out")
  local high=$(safe_grep_count '\[HIGH\]' "$out")
  local cl=$(safe_grep_count -i 'CROSS-LANG|cross.language.free' "$out")
  local own=$(safe_grep_count -i 'ownership.violation' "$out")
  local dang=$(safe_grep_count -i 'danger.surface' "$out")
  local ffi=$(safe_grep_count -i 'FFI.type.mismatch' "$out")

  # 归零空值
  : "${crit:=0}" "${high:=0}" "${cl:=0}" "${own:=0}" "${dang:=0}" "${ffi:=0}"

  local ms=$(awk 'NR==2' "${out}.meta" 2>/dev/null || echo "0")
  printf '%s\n' "${bn},SUCCESS,${ms},${crit},${high},${cl},${own},${dang},${ffi}${extra_col}" >> "$csv"

  # 提取 issues 详情
  grep -E '\[(CRITICAL|HIGH)\]' "$out" 2>/dev/null > "${out}.issues" || true

  echo "OK (${ms}ms C:${crit} H:${high} CL:${cl})"
  return 0
}

# ══════════════════════════════════════════════
# PHASE 1: 基线
# ══════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  PHASE 1: 基线运行（无 Language Override）  ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

CSV1="${RESULTS_DIR}/phase1_baseline.csv"
echo "file,status,time_ms,critical,high,cross_lang,ownership,danger,ffi_type" > "$CSV1"

P1_OK=0 P1_FAIL=0 P1_TO=0

for i in "${!ALL_FILES[@]}"; do
  F="${ALL_FILES[$i]}"; BN=$(basename "$F" .ll); IDX=$((i+1))
  OF="${BASELINE_DIR}/${BN}.txt"; LF="${BASELINE_DIR}/${BN}.log"
  printf "[%2d/%d] 基线: %s ... " "$IDX" "$TOTAL" "$BN"

  if ! run_test "$F" "$OF" "$LF" ""; then
    local_ec=$(awk 'NR==1' "${OF}.meta" 2>/dev/null || echo "?")
    if [ "$local_ec" = "124" ]; then
      echo "TIMEOUT"; P1_TO=$((P1_TO+1))
      printf '%s\n' "${BN},TIMEOUT,60000,0,0,0,0,0,0" >> "$CSV1"
      continue
    fi
  fi
  if extract_and_print "$OF" "$CSV1"; then P1_OK=$((P1_OK+1)); else P1_FAIL=$((P1_FAIL+1)); fi
done

echo ""
echo "--- Phase 1: OK=$P1_OK FAIL=$P1_FAIL TIMEOUT=$P1_TO ---"

# ══════════════════════════════════════════════
# PHASE 2: Override
# ══════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  PHASE 2: Override 运行（Language Override） ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

CSV2="${RESULTS_DIR}/phase2_override.csv"
echo "file,status,time_ms,critical,high,cross_lang,ownership,danger,ffi_type,override_args" > "$CSV2"

P2_OK=0 P2_TO=0

for i in "${!ALL_FILES[@]}"; do
  F="${ALL_FILES[$i]}"; BN=$(basename "$F" .ll); IDX=$((i+1))
  OF="${OVERRIDE_DIR}/${BN}.txt"; LF="${OVERRIDE_DIR}/${BN}.log"
  OVR_ARGS=$(get_override_args "$BN")
  printf "[%2d/%d] Override: %s ... " "$IDX" "$TOTAL" "$BN"

  if ! run_test "$F" "$OF" "$LF" "$OVR_ARGS"; then
    local_ec=$(awk 'NR==1' "${OF}.meta" 2>/dev/null || echo "?")
    if [ "$local_ec" = "124" ]; then
      echo "TIMEOUT"; P2_TO=$((P2_TO+1))
      printf '%s\n' "${BN},TIMEOUT,60000,0,0,0,0,0,0,${OVR_ARGS}" >> "$CSV2"
      continue
    fi
  fi
  if extract_and_print "$OF" "$CSV2" ",${OVR_ARGS}"; then P2_OK=$((P2_OK+1)); fi
done

echo ""
echo "--- Phase 2: OK=$P2_OK TIMEOUT=$P2_TO ---"

echo ""
echo "=============================================="
echo " 测试完成！结果在 ${RESULTS_DIR}/"
echo "=============================================="
