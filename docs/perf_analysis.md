# OmniScope 性能瓶颈分析报告

> 分析日期：2026-05-30
> 测试目标：`./corpus/real_world/other/wasmtime_test.bc`
> 测试环境：macOS, Apple Silicon, LLVM-22
> 基准耗时：100.2s（`./zig-out/bin/OmniScope ./corpus/real_world/other/wasmtime_test.bc`）
> 函数数量：5293

## 1. 实测数据：各 Pass 耗时分布

使用 `--perf-stats` 采集，单位 ms：

| Pass | 时间 (ms) | 占比 | 累计 |
|------|----------|------|------|
| pointer-ownership | 26,023 | 26.0% | 26.0% |
| cross-lang-dataflow | 23,255 | 23.2% | 49.2% |
| SemanticResolver | 11,824 | 11.8% | 61.0% |
| error-propagation-tracer | 9,583 | 9.6% | 70.6% |
| ptr-lifetime | 7,278 | 7.3% | 77.8% |
| pointer-flow (taint) | 6,378 | 6.4% | 84.2% |
| call-graph | 3,814 | 3.8% | 88.0% |
| ffi-boundary | 2,825 | 2.8% | 90.8% |
| gc-safety | 2,808 | 2.8% | 93.6% |
| free-validation | 730 | 0.7% | 94.4% |
| alias | 678 | 0.7% | 95.0% |
| ffi-type-mismatch | 603 | 0.6% | 95.6% |
| callback-escape | 400 | 0.4% | 96.0% |
| surface-classifier | 317 | 0.3% | 96.3% |
| memory-safety | 293 | 0.3% | 96.6% |
| danger-surface | 210 | 0.2% | 96.8% |
| rust-ffi-filter | 1,691 | 1.7% | 98.5% |
| return-check | 800 | 0.8% | 99.3% |
| 其余 (cfg/lock/dfg/integer-overflow/buffer-overflow/malloc-check/ffi-unsafe/ffi-body-check) | ~721 | 0.7% | 100.0% |
| **TOTAL** | **100,214** | **100%** | |

**结论：前 5 个 pass 占 78% 时间，前 2 个 pass 占 49% 时间。**

---

## 2. 根因分析：重复指令遍历

### 2.1 问题描述

每个 pass 内部独立遍历 LLVM IR 的 `Function → BasicBlock → Instruction` 层级结构。
不同 pass 之间没有共享遍历结果，同一条指令被 20+ 个 pass 反复访问。

每次指令访问涉及 5-16 次 LLVM FFI 调用（`LLVMGetInstructionOpcode`、`LLVMGetNumOperands`、`LLVMGetOperand`、`LLVMGetValueName` 等）。

### 2.2 各 Pass 内部遍历次数统计

通过 `grep -c "LLVMGetFirstBasicBlock\|LLVMGetNextBasicBlock\|LLVMGetFirstInstruction\|LLVMGetNextInstruction"` 统计每个文件中的嵌套遍历循环数：

| Pass 源文件 | 循环数 | 说明 |
|------------|--------|------|
| `src/pass/analysis/ffi/cross_lang_dataflow.zig` | 10 | 5 个独立的 `func→bb→inst` 遍历（行 134, 214, 294, 371, 514） |
| `src/types/ownership_analysis.zig` | 4 | 2 个独立遍历（行 70 `analyzeFunctionForOwnership`，行 127 `checkOwnershipTransferForFunction`） |
| `src/pass/analysis/ptr_lifetime/ptr_lifetime.zig` | 3 | 2 个独立遍历（行 560 CFG 构建，行 578 指令分析） |
| `src/pass/analysis/ffi/error_propagation_tracer.zig` | 6 | 3 个独立遍历（行 158, 254, 351） |
| `src/pass/analysis/taint/taint_propagation.zig` | 6 | 3 个独立遍历（行 145, 156, 834） |
| `src/pass/analysis/pointer_ownership.zig` | 2 | 1 个遍历（行 280）+ 调用 `ownership_analysis` |
| `src/pass/analysis/call_graph.zig` | 2 | 1 个遍历（行 212） |
| `src/pass/analysis/semantic_resolver_pass.zig` | 2 | 1 个遍历（行 67）+ 调用 `library_alloc_pairs` |
| `src/semantics/patterns/library_alloc_pairs.zig` | 2 | 1 个遍历（行 145） |
| `src/pass/analysis/gc_safety.zig` | 2 | 1 个遍历 |

### 2.3 每条指令的 FFI 调用数

逐个循环统计 `c.LLVM*` 调用次数：

| 文件 | 循环起始行 | FFI 调用数/指令 |
|------|-----------|----------------|
| cross_lang_dataflow.zig | 134 | 7 |
| cross_lang_dataflow.zig | 214 | 12 |
| cross_lang_dataflow.zig | 294 | 9 |
| cross_lang_dataflow.zig | 371 | 7 |
| cross_lang_dataflow.zig | 514 | 9 |
| ownership_analysis.zig | 70 | 7 |
| ownership_analysis.zig | 127 | 12 |
| ptr_lifetime.zig | 560 | 16 |
| ptr_lifetime.zig | 578 | 12 |

### 2.4 总量估算

```
假设 wasmtime_test.bc 有 ~500,000 条指令（5293 函数 × ~100 指令/函数）

全量遍历次数：~20 次
每指令 FFI 调用：~10 次（平均）
总 FFI 调用数：20 × 500,000 × 10 = ~100,000,000 次（1 亿次）

每次 FFI 调用开销：~100-500 ns（Zig→C 边界 + LLVM 内部）
纯 FFI 开销：1 亿 × 200ns = ~20s

加上 LLVM 内部遍历开销（指针解引用、链表遍历）：
实际耗时 ≈ 100s（与实测一致）
```

---

## 3. 优化方案

### 核心原则：不损失精度

所有方案只优化**数据收集方式**，不改变**分析逻辑和判定规则**。
最终检测结果必须与当前版本 bit-for-bit 一致。

---

### 方案 1：指令元数据缓存层（P0）

#### 问题

同一条指令被 20 个 pass 反复调用：
- `c.LLVMGetInstructionOpcode(inst)` → 每条指令被调用 ~20 次
- `c.LLVMGetNumOperands(inst)` → 每条 call 指令被调用 ~10 次
- `c.LLVMGetOperand(inst, i)` → 每条 call 指令被调用 ~15 次
- `c.LLVMGetValueName(callee)` → 每条 call 指令被调用 ~8 次

这些数据在 LLVM IR 生命周期内不变，完全可以缓存。

#### 方案

在 Pipeline 初始化阶段（`setModule` 之后、`run` 之前）做一次遍历，
把所有指令的元数据缓存到连续内存：

```zig
// src/ir/inst_cache.zig

const CachedInst = struct {
    llvm_ref: c.LLVMValueRef,       // 原始 LLVM 指针（用于关联）
    opcode: c_uint,                  // LLVMGetInstructionOpcode
    num_operands: c_int,             // LLVMGetNumOperands
    callee_name_hash: u64,           // hash(LLVMGetValueName(callee))，仅 call 指令有效
    parent_bb_id: u32,               // 所属 basic block 的 ID
    parent_func_id: u32,             // 所属 function 的 ID
    flags: u8,                       // bit 0: is_call, bit 1: is_invoke, bit 2: is_ret, bit 3: is_store, bit 4: is_load
};

const InstCache = struct {
    insts: []CachedInst,             // 连续数组，按遍历顺序排列
    llvm_to_idx: std.AutoHashMap(u64, u32),  // LLVMValueRef → 数组下标
    func_names: [][]const u8,        // 函数名缓存（按 func_id 索引）
    func_name_hashes: []u64,         // 函数名哈希（按 func_id 索引）

    pub fn init(module: c.LLVMModuleRef, allocator: Allocator) !InstCache {
        // 单次遍历：Function → BB → Instruction
        // 构建 insts 数组和 llvm_to_idx 映射
    }

    pub fn getOpcode(self: *const InstCache, inst: c.LLVMValueRef) c_uint {
        const idx = self.llvm_to_idx.get(@intFromPtr(inst)) orelse return c.LLVMGetInstructionOpcode(inst);
        return self.insts[idx].opcode;
    }

    pub fn getNumOperands(self: *const InstCache, inst: c.LLVMValueRef) c_int {
        const idx = self.llvm_to_idx.get(@intFromPtr(inst)) orelse return c.LLVMGetNumOperands(inst);
        return self.insts[idx].num_operands;
    }

    // ... 类似地实现 getOperand, getCalleeName, isCall, etc.
};
```

#### 改造点

所有 pass 中的 `c.LLVMGetInstructionOpcode(inst)` 替换为 `cache.getOpcode(inst)`。
`c.LLVMGetValueName` 同理。

**关键约束**：`c.LLVMGetOperand` 不缓存（因为 operand 是动态值，不同 pass 需要不同 operand 索引）。
只缓存 `opcode`、`num_operands`、`callee_name` 这三个每条指令确定不变的属性。

#### 预估收益

| 消除的 FFI 调用 | 当前次数 | 优化后 |
|----------------|---------|--------|
| LLVMGetInstructionOpcode | ~1000 万 | 50 万（仅缓存构建时） |
| LLVMGetNumOperands | ~500 万 | 0 |
| LLVMGetValueName | ~400 万 | 5293（仅函数级） |
| **总计** | **~1900 万** | **~50 万** |

FFI 调用减少 ~97%，预估耗时从 100s 降至 **50-60s**。

#### 风险

- **低**：缓存的是 LLVM IR 中不可变的结构属性，不涉及值语义。
- 需确保 `CachedInst` 数组的生命周期覆盖整个 `run()` 阶段。
- `LLVMGetOperand` 不缓存，避免语义变化。

---

### 方案 2：Pass 内部遍历合并（P1）

#### 问题

以下 pass 内部有多个独立的全量遍历循环，每次都从 `LLVMGetFirstFunction` 开始：

**cross_lang_dataflow.zig**（5 次遍历，23s）：
1. 行 134：扫描所有 call 指令，收集 FFI 调用点
2. 行 214：扫描 store + call 指令，收集跨语言数据流
3. 行 294：扫描 call 指令，检测跨语言 free
4. 行 371：扫描 call 指令，检测 orphan 指针
5. 行 514：扫描 call + store 指令，检测 use-after-free

**pointer_ownership（ownership_analysis.zig）**（3 次遍历，26s）：
1. 行 70：`analyzeFunctionForOwnership` — 收集 alloc/free 站点 + 构建 flow graph
2. 行 127：`checkOwnershipTransferForFunction` — 检测返回值/输出参数的 ownership 转移
3. pointer_ownership.zig 行 280：额外的函数级遍历

**error_propagation_tracer.zig**（3 次遍历，10s）：
1. 行 158：扫描 call 指令，收集 FFI 调用
2. 行 254：扫描 call 指令，检测错误传播
3. 行 351：扫描 call 指令，检测异常处理

**taint_propagation.zig**（3 次遍历，6s）：
1. 行 145：扫描 call 指令，收集 taint 源
2. 行 156：扫描 call 指令，传播 taint
3. 行 834：扫描 call 指令，检测 sink

#### 方案

将每个 pass 内部的多次遍历合并为单次遍历：

```zig
// cross_lang_dataflow 优化后：单次遍历
fn analyzeModule(ctx, mod) void {
    var func = LLVMGetFirstFunction(mod);
    while (func != null) {
        var bb = LLVMGetFirstBasicBlock(func);
        while (bb != null) {
            var inst = LLVMGetFirstInstruction(bb);
            while (inst != null) {
                const opcode = cache.getOpcode(inst);

                if (isCallOrInvoke(opcode)) {
                    // 原遍历 1：收集 FFI 调用点
                    collectFFICall(inst, ...);
                    // 原遍历 3：检测跨语言 free
                    detectCrossLangFree(inst, ...);
                    // 原遍历 4：检测 orphan 指针
                    detectOrphanPointer(inst, ...);
                }

                if (opcode == LLVMStore) {
                    // 原遍历 2：收集跨语言数据流
                    collectCrossLangStore(inst, ...);
                }

                // 原遍历 5：检测 use-after-free（需要 alloc/free 信息，延迟到遍历后）
                inst = LLVMGetNextInstruction(inst);
            }
            bb = LLVMGetNextBasicBlock(bb);
        }
        func = LLVMGetNextFunction(func);
    }

    // 遍历后处理：用收集到的数据做跨指令分析
    detectUseAfterFree(...);
}
```

#### 预估收益

| Pass | 当前遍历 | 合并后 | 当前耗时 | 预估耗时 |
|------|---------|--------|---------|---------|
| cross-lang-dataflow | 5 | 1 | 23,255ms | ~5,000ms |
| pointer-ownership | 3 | 1 | 26,023ms | ~9,000ms |
| error-propagation | 3 | 1 | 9,583ms | ~3,500ms |
| pointer-flow (taint) | 3 | 1 | 6,378ms | ~2,500ms |
| ptr-lifetime | 2 | 1 | 7,278ms | ~4,000ms |

合计节省：~42,000ms → 预估耗时从 100s 降至 **58s**。

#### 风险

- **中**：需要理解每个遍历循环的输出如何被后续逻辑使用。
- 部分遍历有依赖关系（如遍历 5 需要遍历 1-4 的结果），需要调整执行顺序。
- **不改变分析逻辑**，只改变遍历次数。

---

### 方案 3：FFI 函数预筛选（P2）

#### 问题

所有 pass 对全部 5293 个函数做完整分析，但大部分函数没有 FFI 调用。
wasmtime 是 Rust 项目，FFI 调用主要集中在少数与 C 交互的模块。

#### 方案

在 Pipeline 初始化阶段做一次快速预筛选：

```zig
const FuncProfile = struct {
    has_ffi_call: bool,        // 包含对外部声明函数的调用
    has_alloc_call: bool,      // 包含 malloc/free 等分配函数调用
    has_store: bool,           // 包含 store 指令
    call_count: u32,           // call 指令数量
    inst_count: u32,           // 指令总数
};

fn prefilterFunctions(module: c.LLVMModuleRef, allocator: Allocator) !std.AutoHashMap(u32, FuncProfile) {
    // 单次遍历，为每个函数建立 profile
    // 只检查 call 指令的 callee 是否为 LLVMIsDeclaration
}
```

然后各 pass 在遍历时跳过不相关的函数：

```zig
// cross_lang_dataflow：只处理 has_ffi_call 的函数
// pointer_ownership：只处理 has_alloc_call 的函数
// ptr_lifetime：只处理 has_alloc_call || has_store 的函数
```

#### 预估收益

假设 wasmtime 5293 个函数中只有 ~500 个有 FFI 调用（~10%）：
- 非 FFI 函数的遍历开销消除 → 预估节省 30-40% 的遍历时间
- 但分析逻辑（flow graph 构建等）仍需处理所有函数 → 实际节省 10-20%

预估耗时从 100s 降至 **80-90s**。

#### 风险

- **低**：预筛选只跳过确定没有 FFI 调用的函数，不会遗漏。
- 需要确认哪些 pass 可以安全跳过非 FFI 函数。
- `ptr_lifetime` 可能需要分析所有函数（因为 alloc/free 不一定是 FFI），需要仔细验证。

---

### 方案 4：函数名分类缓存（P3）

#### 问题

每条 call 指令都需要：
1. `c.LLVMGetValueName(callee)` → 获取 callee 名称
2. `std.mem.span(name)` → 转换为 Zig 切片
3. `classifyAllocLanguage(name)` / `isFreeFunction(name)` / `FuzzyMatcher.classify(name)` → 字符串匹配

同一个 callee 函数可能被调用数千次，每次都重复上述步骤。

#### 方案

```zig
// 在 InstCache 构建阶段，一次性分类所有函数
const FuncClass = struct {
    alloc_class: ?Language,      // classifyAllocLanguageEnum 的结果
    free_class: ?[]const u8,     // classifyFreeLanguage 的结果
    fuzzy_class: ?FuzzyKind,     // FuzzyMatcher.classify 的结果
    is_alloc: bool,              // isAllocationFunction 的结果
    is_free: bool,               // isFreeFunction 的结果
};

var func_classes: std.AutoHashMap(u32, FuncClass);  // func_id → FuncClass
```

在遍历 call 指令时，通过 `inst_cache.getCalleeFuncId(inst)` 获取 func_id，
然后直接查表，不做字符串比较。

#### 预估收益

- 消除每个 call 指令的 2-5 次字符串比较
- 字符串比较本身不是热点（~5%），但可以减少 cache miss
- 预估耗时从 100s 降至 **92-95s**

#### 风险

- **极低**：纯缓存，结果与当前完全一致。

---

### 方案 5：Flow Graph 扁平化（P4）

#### 问题

当前 flow graph 使用嵌套 HashMap：

```zig
flow_graph: std.AutoHashMap(u32, std.AutoHashMap(u32, void))
```

对于密集图（如 ownership_analysis 的 flow graph），这导致：
- 大量小 HashMap 分配（每个节点一个）
- 哈希计算开销
- 内存碎片

#### 方案

```zig
const FlowGraph = struct {
    // CSR (Compressed Sparse Row) 格式
    offsets: []u32,      // offsets[i] = edges 数组中节点 i 的起始位置
    targets: []u32,      // 所有目标节点，按源节点分组
    edge_count: u32,

    pub fn successors(self: *FlowGraph, node: u32) []const u32 {
        const start = self.offsets[node];
        const end = self.offsets[node + 1];
        return self.targets[start..end];
    }

    pub fn addEdge(self: *FlowGraph, from: u32, to: u32) !void {
        // 构建阶段使用临时 HashMap，最后转 CSR
    }
};
```

#### 预估收益

- 减少内存分配次数（从 O(nodes) 个 HashMap → 2 个数组）
- 减少 cache miss（连续内存 vs 分散的 HashMap 节点）
- 预估耗时从 100s 降至 **92-95s**

#### 风险

- **中**：需要修改 flow graph 的构建和查询接口。
- CSR 格式需要预知节点数或支持动态扩容。
- 需要确保所有使用 flow graph 的代码都适配新接口。

---

## 4. 方案组合与预估总收益

| 组合 | 方案 | 单独收益 | 累积预估 |
|------|------|---------|---------|
| 仅 P0 | 指令缓存层 | 40-50% | 100s → 50-60s |
| P0 + P1 | + 合并遍历 | 30-40% | 100s → 25-35s |
| P0 + P1 + P2 | + 预筛选 | 10-20% | 100s → 20-30s |
| P0 + P1 + P2 + P3 | + 名称缓存 | 5-10% | 100s → 18-27s |
| 全部 | + Flow Graph | 5-10% | 100s → 15-25s |

**保守预估：P0 + P1 组合可将 100s 降至 25-35s（3-4x 加速）。**

---

## 5. 实施注意事项

### 5.1 精度保障

- **所有方案只优化数据收集路径，不改变分析逻辑。**
- 指令缓存只存储不可变的结构属性（opcode、num_operands、callee_name）。
- `LLVMGetOperand` 不缓存（operand 值在不同 pass 语境下可能有不同解读）。
- 每个方案实施后，必须在测试套件上验证结果不变（97 个测试，当前 67/97 通过）。

### 5.2 内存开销

- 指令缓存：500K 指令 × ~40 bytes/CachedInst ≈ 20 MB
- 函数分类缓存：5293 函数 × ~32 bytes/FuncClass ≈ 170 KB
- Flow Graph CSR：取决于边数，通常 < 10 MB
- **总计额外内存 < 30 MB，可接受。**

### 5.3 实施顺序

1. **先做 P0（指令缓存）**：收益最大，风险最低，独立于其他方案。
2. **再做 P1（合并遍历）**：在 P0 基础上进一步优化，需要逐 pass 重构。
3. **P2（预筛选）**：可以在 P0 的缓存构建阶段顺带完成。
4. **P3（名称缓存）**：可以在 P0 的缓存构建阶段顺带完成。
5. **P4（Flow Graph）**：最后做，收益相对小但改动面大。

### 5.4 验证方法

```bash
# 1. 功能验证：测试套件结果不变
zig build test-rust-ffi 2>&1 | grep "passed.*failed"
zig build test-gopyjava-ffi 2>&1 | grep "passed.*failed"
zig build test-cscpp-ffi 2>&1 | grep "passed.*failed"

# 2. 性能验证：wasmtime 耗时对比
time ./zig-out/bin/OmniScope ./corpus/real_world/other/wasmtime_test.bc

# 3. 精度验证：issue 输出 diff
./zig-out/bin/OmniScope ./corpus/real_world/other/wasmtime_test.bc > /tmp/before.json
# ... 实施优化 ...
./zig-out/bin/OmniScope ./corpus/real_world/other/wasmtime_test.bc > /tmp/after.json
diff /tmp/before.json /tmp/after.json  # 必须无差异
```

---

## 6. 附录：完整 FFI 调用链分析

### 6.1 cross_lang_dataflow.zig（23,255ms，5 次遍历）

| 遍历 | 行号 | 目的 | FFI/指令 |
|------|------|------|---------|
| 1 | 134-190 | 收集所有 FFI 调用点（call to external） | 7 |
| 2 | 214-280 | 收集跨语言 store + call 数据流 | 12 |
| 3 | 294-360 | 检测跨语言 free（alloc in lang A, free in lang B） | 9 |
| 4 | 371-495 | 检测 orphan 指针（alloc but never freed/passed） | 7 |
| 5 | 514-580 | 检测 use-after-free across FFI boundary | 9 |

### 6.2 pointer-ownership（26,023ms，3 次遍历）

| 遍历 | 函数 | 目的 | FFI/指令 |
|------|------|------|---------|
| 1 | `analyzeFunctionForOwnership` (行 70) | 收集 alloc/free 站点 + 构建 flow graph | 7 |
| 2 | `checkOwnershipTransferForFunction` (行 127) | 检测 return/param 的 ownership 转移 | 12 |
| 3 | `pointer_ownership.zig` 行 280 | 额外的函数级分析 | ~8 |

### 6.3 error_propagation_tracer.zig（9,583ms，3 次遍历）

| 遍历 | 行号 | 目的 | FFI/指令 |
|------|------|------|---------|
| 1 | 158 | 收集所有 FFI 调用 | ~5 |
| 2 | 254 | 检测错误传播路径 | ~5 |
| 3 | 351 | 检测异常处理 | ~5 |

### 6.4 ptr_lifetime.zig（7,278ms，2 次遍历）

| 遍历 | 行号 | 目的 | FFI/指令 |
|------|------|------|---------|
| 1 | 560 | CFG 构建（bb→bb 边） | 16 |
| 2 | 578 | 指令分析（alloc/free/flow） | 12 |

### 6.5 taint_propagation.zig（6,378ms，3 次遍历）

| 遍历 | 行号 | 目的 | FFI/指令 |
|------|------|------|---------|
| 1 | 145 | 收集 taint 源 | ~4 |
| 2 | 156 | 传播 taint | ~4 |
| 3 | 834 | 检测 taint sink | ~4 |

---


当前成绩：67/97（Rust 17/25 + GoJava 27/36 + Cscpp 23/36）

  Plan 各阶段完成情况

  ┌───────┬────────────────────────────────┬─────────────────────────────────────────────────┬──────────────┐
  │ Phase │              内容              │                      状态                       │     效果     │
  ├───────┼────────────────────────────────┼─────────────────────────────────────────────────┼──────────────┤
  │ 1a    │ FuzzyMatcher 加 _drop/_release │ ✅ 已完成                                       │ 未见明显效果 │
  ├───────┼────────────────────────────────┼─────────────────────────────────────────────────┼──────────────┤
  │ 1b    │ free_validation 对齐           │ ✅ 已完成                                       │ N/A          │
  ├───────┼────────────────────────────────┼─────────────────────────────────────────────────┼──────────────┤
  │ 2     │ isRustAllocCall 扩展           │ ⚠️  只加了 _RZN4alloc5alloc                      │ 部分         │
  ├───────┼────────────────────────────────┼─────────────────────────────────────────────────┼──────────────┤
  │ 3     │ LLVMLoad origin tracking       │ ✅ 已完成                                       │ 未见明显效果 │
  ├───────┼────────────────────────────────┼─────────────────────────────────────────────────┼──────────────┤
  │ 4     │ Allocator 语言分类             │ ⚠️  classify.zig 改动在，但 EXACT_ALLOC_SET 未加 │ 未见明显效果 │
  ├───────┼────────────────────────────────┼─────────────────────────────────────────────────┼──────────────┤
  │ 5     │ 抑制 ffi_unsafe_call 噪音      │ ❌ 未做                                         │ -            │
  ├───────┼────────────────────────────────┼─────────────────────────────────────────────────┼──────────────┤
  │ 6     │ 修复 malloc_unchecked 噪音     │ ❌ 未做                                         │ -            │
  ├───────┼────────────────────────────────┼─────────────────────────────────────────────────┼──────────────┤
  │ 7     │ 测试 bug 修复                  │ ⚠️  只做了 placement new（+1）                   │ +1           │
  └───────┴────────────────────────────────┴─────────────────────────────────────────────────┴──────────────┘

  关键问题分析

  绝大多数失败都是同一个根因：[ch09] Propagation iteration 1: 0 new marks, 0 total

  这意味着 PtrLifetimePass 的指针生命周期传播根本没有工作——指针从分配到释放的 flow 关系没有建立起来。这影响了：
  - 所有 C#/Zig 跨语言 bug 检测（Cscpp 13个失败中有10个是这个原因）
  - 多个 Rust bug 检测（8个失败中有5个）
  - 多个 Go/Java bug 检测（9个失败中有3个）
  
  不是 Phase 1-4 改动没用，而是核心传播机制没被触发。 Phase 1-4 解决的是"识别正确语言"的问题，但"检测到 bug"需要 flow graph 传播先工作起来。

  另外 4 个 cscpp 回退（27→23）应该是之前 linter 的某些优化（如 inst_cache、cpp_fp_reduction 改动）意外地让部分测试通过了，恢复到 b861504 后这些优化丢失。

  建议优先级

  与其逐个修补 pattern，不如先解决根因：为什么 0 new marks？是 early_exit 阻止了 PtrLifetimePass 运行？还是 flow graph 建立不完整？这是优先级最高的问题。
