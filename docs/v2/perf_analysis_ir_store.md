# 性能根因分析 & IR Store 方案

## 一、141.5s 根因分析

### PERF 全景

| Pass | 耗时 | 占比 | 备注 |
|---|---|---|---|
| **rust-ffi-filter** | **141.5s** | **68.5%** | 主瓶颈 |
| pointer-ownership | 14.4s | 7.0% | 已优化为单次遍历 |
| SemanticResolver | 12.8s | 6.2% | 外层合并但内层 10 个检测器仍在扫 |
| error-propagation-tracer | 7.2s | 3.5% | 已做语言门控 |
| ptr-lifetime | 7.3s | 3.5% | |
| pointer-flow | 6.2s | 3.0% | |
| cross-lang-dataflow | 3.4s | 1.7% | |
| call-graph | 3.8s | 1.8% | |
| ffi-boundary | 2.8s | 1.4% | |
| others | ~7s | 3.4% | |
| **Total** | **~206s** | **100%** | |

### rust-ffi-filter 热点拆解

`auditFunction()` 伪执行流：

```zig
fn auditFunction(func, ctx, diag) {
    // ─── 收集指令（1 次遍历）────────────────
    all_insts = collectAllInstructions(func)    // 1 × BB/inst

    // ─── 规则 1-5：各自独立遍历 ─────────────
    detectAsPtrEscape(func, ctx, diag, &inst_cache)         // 1 × BB/inst ← 多余
    detectCrossLangMismatch(func, ctx, diag, &inst_cache)   // 1 × BB/inst ← 多余
    detectUnsafeFfiCalls(func, &inst_cache)                 // 1 × BB/inst ← 多余
    detectStackEscapeToFFI(func, ctx, diag, &inst_cache)    // 1 × BB/inst ← 多余
    detectOwnershipTransferViolations(func, ctx, diag, &inst_cache) // 1 × BB/inst ← 多余

    // ─── 规则 7-10：已用 insts slice ──────────
    lifetime_rules.detectAsPtrDangling(self, func, insts, ...)   // for(insts) ✓
    lifetime_rules.detectCallbackOwnershipRisk(self, func, insts, ...) // for(insts) ✓
    advanced_rules.detectWriteToImmutable(self, func, insts, ...) // for(insts) ✓
    advanced_rules.detectUseAfterFree(self, func, insts, ...)     // for(insts) ✓

    // ─── 值追踪：每次调用都做独立遍历 ────────
    traceValueSource(arg, func)      // 可能触发 traceAllocaContent → 遍历所有指令
    traceValueUsage(val, func)       // 遍历所有指令寻找 use-site
    valueTracesTo(user, source)      // 递归遍历寻找 store-to-alloca
}

// 以上为 1 个函数。wasmtime 有 ~4000 个函数。
// 规则 1-5 多余遍历：5 × 4000 = 20000 次独立 BB/inst 扫描
```

**根本原因 — 积累的 4 层冗余**

| 层次 | 表现 | 位置 |
|---|---|---|
| **L1 — 跨 pass 冗余** | 每个 pass 独立扫全模块；出 pointer_ownership 和 ptr_lifetime 都在做相似的分配器遍历 | pipeline 层 |
| **L2 — pass 内规则冗余** | 5 个基本规则各自遍历函数，尽管指令列表已在 `auditFunction` 收集 | rust_ffi_rules_basic.zig |
| **L3 — 值追踪冗余** | `traceValueSource()` / `traceAllocaContent()` 每次调用都扫全部指令，无缓存 | value_tracking.zig |
| **L4 — LLVM C FFI 开销** | 每次 `LLVMGetInstructionOpcode()` 等调用跨越 Zig→C 边界，累计数千万次 | 全代码库 |

### 为什么现有 InstCache 不够

当前 InstCache（`src/ir/inst_cache.zig`）设计局限：

```
┌──────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Pass A   │────→│ InstCache 1  │────→│ LLVM C API   │     │              │
│          │     │ (per-function)│     │              │     │              │
│ Pass B   │────→│ InstCache 2  │────→│ LLVM C API   │     │              │
│          │     │ (per-function)│     │              │     │              │
│ Pass C   │────→│ InstCache 3  │────→│ LLVM C API   │     │  浪费 3×    │
│          │     │ (per-function)│     │              │     │              │
└──────────┘     └──────────────┘     └──────────────┘     └──────────────┘
 每个 pass 建自己的 cache，且缓存在函数结束时销毁
```

---

## 二、IR Store 方案

### 核心目标

**一次收集、全局共享、按需查询。**

### 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                     Pipeline Init                           │
│  collectModuleIR(mod, allocator) → *ModuleIRStore           │
│  ctx.ir_store = &store  (注入 PassContext)                  │
└─────────────────────────────────────────────────────────────┘
                           │
              ┌────────────┼────────────┬──────────────┐
              ▼            ▼            ▼              ▼
         ┌─────────┐ ┌─────────┐ ┌─────────┐  ┌──────────────┐
         │ Pass A  │ │ Pass B  │ │ Pass C  │  │ ValueTracker  │
         │         │ │         │ │         │  │ (跨 pass 共享) │
         └────┬────┘ └────┬────┘ └────┬────┘  └──────┬───────┘
              │           │           │               │
              └───────────┴───────────┴───────────────┘
                          │
                          ▼
                  ┌───────────────┐
                  │ ModuleIRStore │  ← 全局共享，只读
                  │  (Zig struct) │
                  └───────────────┘
```

### 核心数据结构

```zig
/// 模块级 IR 存储 — 一次构建，全局共享
pub const ModuleIRStore = struct {
    allocator: Allocator,
    
    /// 函数索引：name → FunctionIR
    functions: StringHashMap(*FunctionIR),
    /// 函数有序列表（保持遍历顺序）
    function_list: []*FunctionIR,

    // ─── 全局查询索引（可选预热）────────────
    /// 模块内所有全局变量
    globals: []LLVMValueRef,
    /// 全局变量名称索引
    global_names: StringHashMap(usize),

    // 统计信息
    function_count: usize,
    total_instruction_count: usize,
};

/// 函数级 IR 存储 — 一次遍历，所有数据就绪
pub const FunctionIR = struct {
    func: LLVMValueRef,
    name: []const u8,     // LLVM-owned, 不需要 free
    
    /// 所有指令（按 BB 顺序平铺）
    instructions: []const LLVMValueRef,
    
    // ─── 预计算索引（一次遍历完成）─────────
    /// 快速分类查询 — 按 opcode 分桶
    calls:        []const LLVMValueRef,  // call/invoke 指令
    stores:       []const LLVMValueRef,  // store 指令
    loads:        []const LLVMValueRef,  // load 指令
    allocas:      []const LLVMValueRef,  // alloca 指令
    returns:      []const LLVMValueRef,  // ret 指令
    geps:         []const LLVMValueRef,  // GEP 指令
    bitcasts:     []const LLVMValueRef,  // bitcast 指令
    
    // ─── 预计算元数据 ─────────────────────
    /// 指令 opcode 缓存（对应现有 InstCache）
    opcodes: []const c_uint,
    /// 类型模式：指针类型指令索引
    pointer_type_insts: []const usize,
    
    // ─── 快速查询方法 ─────────────────────
    /// 是否为 call/invoke
    pub fn isCall(self, idx: usize) bool;
    /// 获取 callee name（已缓存，0 LLVM 调用）
    pub fn getCalleeName(self, idx: usize) ?[]const u8;
    /// 按分类遍历（替代 for(insts) + 判断 opcode）
    pub fn forEachCall(self, callback: fn(inst, idx) void) void;
};
```

### 收集逻辑（一次性）

```zig
pub fn collectModuleIR(mod: LLVMModuleRef, allocator: Allocator) !ModuleIRStore {
    var store = ModuleIRStore{
        .allocator = allocator,
        .functions = StringHashMap(*FunctionIR).init(allocator),
        .function_list = try allocator.alloc(*FunctionIR, guess_function_count(mod)),
        .globals = &.{},
        .global_names = StringHashMap(usize).init(allocator),
        .function_count = 0,
        .total_instruction_count = 0,
    };

    var func = LLVMGetFirstFunction(mod);
    var func_idx: usize = 0;
    while (func != null) : (func = LLVMGetNextFunction(func)) {
        if (LLVMIsDeclaration(func)) continue;
        
        // 第一次且唯一一次遍历该函数
        var insts = std.ArrayList(LLVMValueRef).init(allocator);
        var calls = std.ArrayList(LLVMValueRef).init(allocator);
        var stores = std.ArrayList(LLVMValueRef).init(allocator);
        // ... 其他分类
        var opcodes = std.ArrayList(c_uint).init(allocator);
        
        var bb = LLVMGetFirstBasicBlock(func);
        while (bb != null) : (bb = LLVMGetNextBasicBlock(bb)) {
            var inst = LLVMGetFirstInstruction(bb);
            while (inst != null) : (inst = LLVMGetNextInstruction(inst)) {
                insts.append(inst);
                const opcode = LLVMGetInstructionOpcode(inst);
                opcodes.append(opcode);
                // 一次遍历完成全部分桶 + 元数据收集
                switch (opcode) {
                    LLVMCall, LLVMInvoke => calls.append(inst),
                    LLVMStore => stores.append(inst),
                    LLVMLoad => loads.append(inst),
                    // ...
                }
            }
        }
        
        store.function_list[func_idx] = createFunctionIR(
            func, name, insts, calls, stores, ..., opcodes
        );
        func_idx += 1;
        store.total_instruction_count += insts.len;
    }
    store.function_count = func_idx;
    return store;
}
```

### 查询 API（替代分散的遍历）

```zig
/// 替代 detectAsPtrEscape 中的 while(bb){while(inst)} 
pub fn findAsPtrCalls(fir: *const FunctionIR) []const LLVMValueRef {
    // 直接返回预分类的 call 指令，无需遍历
    return fir.calls;
}

/// 替代 traceAllocaContent 的全量扫描
pub fn findStoresToAlloca(fir: *const FunctionIR, alloca: LLVMValueRef) ?LLVMValueRef {
    // 只在 stores 子集中查找，而非遍历全部指令
    for (fir.stores) |store| {
        if (LLVMGetOperand(store, 1) == alloca) return store;
    }
    return null;
}

/// 替代 traceValueUsage 的全量扫描
pub fn findUsages(fir: *const FunctionIR, target: LLVMValueRef) UsageSet {
    // 在 stores+calls+geps 子集中搜索（跳过无关的指令类型）
    // ...
}
```

---

## 三、三阶段实施计划

### 阶段 1：快速修复（1-2 天，省 ~40s）

不引入 IR Store，只做 rust-ffi-filter 的指令列表共享：

| 改动 | 文件 | 效果 |
|---|---|---|
| `detectAsPtrEscape` 接受 `insts` slice，删除内部遍历 | rust_ffi_rules_basic.zig | ∓5 次遍历/函数 → for(insts) |
| `detectCrossLangMismatch` 同上 | rust_ffi_rules_basic.zig | |
| `detectUnsafeFfiCalls` 同上 | rust_ffi_rules_basic.zig | |
| `detectStackEscapeToFFI` 同上 | rust_ffi_rules_basic.zig | |
| `detectOwnershipTransferViolations` 同上 | rust_ffi_rules_basic.zig | |
| `traceAllocaContent` 改为只在 `stores` 子集搜索 | value_tracking.zig | traceValueSource 从 O(n) → O(stores) |
| `traceValueUsage` 改为只在 `calls+stores+geps` 搜索 | value_tracking.zig | traceValueUsage O(n) → O(calls+stores) |

预期：141.5s → ~100s（省 ~40s，5 次遍历 + 值追踪加速）

### 阶段 2：IR Store 核心（3-5 天，省 ~60s）

1. **建 `ModuleIRStore` 数据结构** — `src/ir/ir_store.zig`
2. **集成到 pipeline** — 在 `run()` 开始一次性收集，注入 `ctx.ir_store`
3. **迁移所有 pass** — 逐个 pass 从 `LLVMGetFirstBasicBlock` 切到 `ctx.ir_store.functions`
4. **淘汰 `InstCache`** — `ModuleIRStore` 内置 opcode 缓存，覆盖原有功能

预期：~100s → ~40s（消除跨 pass 冗余遍历）

### 阶段 3：值追踪引擎重构（3-5 天，省 ~20s）

| 当前 | 未来 |
|---|---|
| 按需遍历 → 扫描全部指令 | 预构建 def-use 链 |
| 每次 query 扫描 O(n) | 预计算 use-site 索引，O(1) 查表 |
| 递归追踪 → 每次重新展开 GEP | 预计算 value → base 映射 |

预期：~40s → ~20s

---

## 四、关键风险与决策

### 内存权衡

```
当前：每个 pass 独立 cache（~1-2MB/函数周期内）
IR Store：全量常驻（wasmtime 4000 函数 × ~100 instr ≈ 4MB + 索引 ≈ 8MB）
结论：12MB 额外内存换 80% 耗时缩减，权衡极佳
```

### 线程安全

当前架构是单线程 pipeline，`ModuleIRStore` 在 `run()` 开始构建，后续只读。无需锁。

### 与现有 InstCache 的关系

阶段 1 保持 InstCache 不变（只是减少创建次数）。
阶段 2 将 InstCache 功能内联到 `FunctionIR.opcodes[]`，彻底取代。

---

## 五、建议优先级

```
本周：
  └── 阶段 1：rust-ffi-filter 5 规则改用 insts slice（1-2 天）
  └── 完整 27-pass PERF 日志（已拿到数据）

下周：
  └── 阶段 2：IR Store v1（ModuleIRStore + 前 5 个 pass 迁移）

下月：
  └── 阶段 3：值追踪引擎重构
  └── 全 pass 迁移完成

日标：220s → 60s 以内
经期：3 周迭代
投入：~10 人天
```
