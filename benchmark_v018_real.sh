#!/bin/bash

# OmniScope v0.1.8 Real Benchmark
# 收集真实运行数据，不用任何缓存或假设

OUTPUT_FILE="benchmark_v018_real_data.txt"
JSON_DIR="benchmark_v018_json"

echo "=== OmniScope v0.1.8 Real Benchmark ===" | tee "$OUTPUT_FILE"
echo "Date: $(date -Iseconds)" | tee -a "$OUTPUT_FILE"
echo "Binary: $(ls -lh zig-out/bin/OmniScope | awk '{print $5}')" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

mkdir -p "$JSON_DIR"

# 定义测试文件
RED_TEAM=(
    "corpus/red_team_test/subtle_unsafe_rs.ll"
    "corpus/red_team_test/ffi_boundary_bugs.ll"
    "corpus/red_team_test/red_team_bugs.ll"
    "corpus/red_team_test/posix_ffi_bugs.ll"
    "corpus/red_team_test/python_c_api_bugs.ll"
    "corpus/red_team_test/cross_lang_free_bugs.ll"
    "corpus/red_team_test/jni_boundary_bugs_O0.ll"
)

REAL_WORLD=(
    "corpus/real_world/other/sqlite3.ll"
    "corpus/real_world/other/curl8.ll"
    "corpus/real_world/other/ripgrep141.ll"
    "corpus/real_world/other/jsoncpp195.ll"
    "corpus/real_world/other/libuv150.ll"
    "corpus/real_world/zkp/ring.ll"
    "corpus/real_world/zkp/blst.ll"
    "corpus/real_world/zkp/zkcrypto_bls12_381.ll"
)

# 函数：提取JSON数据
extract_data() {
    local json="$1"
    local funcs=$(echo "$json" | grep -m1 '"functions"' | sed 's/.*:\([0-9]*\).*/\1/')
    local issues=$(echo "$json" | grep -m1 '"issues"' | sed 's/.*:\([0-9]*\).*/\1/')
    local time_ms=$(echo "$json" | grep -m1 '"time_ms"' | sed 's/.*:\([0-9]*\).*/\1/')
    
    echo "${funcs:-0}|${issues:-0}|${time_ms:-0}"
}

# 函数：运行单个测试
run_test() {
    local file="$1"
    local name=$(basename "$file" .ll)
    
    if [ ! -f "$file" ]; then
        echo "  [SKIP] $name - file not found" | tee -a "$OUTPUT_FILE"
        return
    fi
    
    echo "Testing: $name" >&2
    
    # 运行并计时
    local start=$(date +%s%N)
    local output=$(./zig-out/bin/OmniScope "$file" --json 2>&1)
    local end=$(date +%s%N)
    local elapsed_ms=$(( (end - start) / 1000000 ))
    
    # 保存JSON
    echo "$output" > "$JSON_DIR/${name}.json"
    
    # 提取数据
    local data=$(extract_data "$output")
    local funcs=$(echo "$data" | cut -d'|' -f1)
    local issues=$(echo "$data" | cut -d'|' -f2)
    
    # 提取FFI边界数
    local ffi_bounds=$(echo "$output" | grep "found.*FFI boundaries" | sed 's/.*found \([0-9]*\) FFI.*/\1/' | head -1)
    local ffi_bounds=${ffi_bounds:-0}
    
    # 提取跨语言边数
    local cross_lang=$(echo "$output" | grep "extracted.*cross-language edges" | sed 's/.*extracted \([0-9]*\) cross.*/\1/' | head -1)
    local cross_lang=${cross_lang:-0}
    
    # 提取指针跟踪数
    local ptrs=$(echo "$output" | grep "tracked.*ptrs" | sed 's/.*tracked \([0-9]*\) ptrs.*/\1/' | head -1)
    local ptrs=${ptrs:-0}
    
    printf "  %-30s funcs=%-5s issues=%-3s ffi=%-5s cross=%-5s ptrs=%-6s time=%sms\n" \
        "$name" "$funcs" "$issues" "$ffi_bounds" "$cross_lang" "$ptrs" "$elapsed_ms" | tee -a "$OUTPUT_FILE"
}

# 红队测试
echo "=== Red Team Tests ===" | tee -a "$OUTPUT_FILE"
for f in "${RED_TEAM[@]}"; do
    run_test "$f"
done

echo "" | tee -a "$OUTPUT_FILE"

# 真实世界项目
echo "=== Real World Projects ===" | tee -a "$OUTPUT_FILE"
for f in "${REAL_WORLD[@]}"; do
    run_test "$f"
done

echo "" | tee -a "$OUTPUT_FILE"
echo "=== Benchmark Complete ===" | tee -a "$OUTPUT_FILE"
echo "JSON files saved to: $JSON_DIR/" | tee -a "$OUTPUT_FILE"
