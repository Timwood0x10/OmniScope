# SemanticResolver Detector 合并优化设计方案

## 📊 当前状态分析

### 发现的问题

**代码位置**: [semantic_resolver_pass.zig](src/pass/analysis/semantic_resolver_pass.zig)

虽然代码注释声称已经从 13 次遍历优化到 2 次（第 57-63 行），但实际实现存在**严重的性能浪费**：

```zig
// 第 107-139 行：11 个 detector 独立遍历
nomicon_ch04.detectFunction(func, raw_mod, srt, diag);   // 遍历1: 所有BB/指令
nomicon_ch05.detectFunction(func, raw_mod, srt, diag);   // 遍历2: 所有BB/指令
nomicon_ch06.detectFunction(func, raw_mod, srt, diag);   // 遍历3: 所有BB/指令
// ... 共 11 次完整函数遍历
```

### 14个 Detector 职责矩阵

| # | Detector | 文件 | 关注点 | 遍历类型 | 当前开销 |
|---|----------|------|--------|----------|----------|
| 1 | **ch04_conversions** | nomicon/ch04 | BitCast, PtrToInt, IntToPtr | 指令级 | 完整遍历 |
| 2 | **ch05_uninitialized** | nomicon/ch05 | Call(assume_init), Load | 指令级 | 完整遍历 |
| 3 | **ch06_obrm** | nomicon/ch06 | Call(free/drop), Store | 指令级 | 完整遍历 |
| 4 | **ch08_concurrency** | nomicon/ch08 | Call(thread/sync) | 指令级 | 完整遍历 |
| 5 | **ch09_vec_box** | nomicon/ch09 | GEP,Load,BitCast,PHI,Call | 数据流 | 固定点迭代* |
| 6 | **ch10_pin_box** | nomicon/ch10 | Call(pin/box) | 指令级 | 完整遍历 |
| 7 | **posix_syscalls** | nomicon/posix | Call(posix_*) | 指令级 | 完整遍历 |
| 8 | **param_attr** | patterns/param_attr | 函数参数属性 | 函数级 | 参数扫描 |
| 9 | **heap_provenance** | patterns/heap_prov | Alloca(DI),Call(alloc),GEP,Load | 指令级 | 完整遍历 |
| 10 | **interior_mut** | patterns/interior_mut | Cell<>, RefCell<> | 指令级 | 完整遍历 |
| 11 | **into_raw_transfer** | patterns/into_raw | Call(into_raw/from_raw) | 指令级 | 完整遍历 |
| 12 | **library_alloc_pairs** | patterns/lib_alloc | Call(malloc/free pairs) | 指令级 | 完整遍历 |
| 13 | **lang_detector** | patterns/lang_detector | 函数命名模式 | 模块级 | 单次查询 |
| 14 | **ResolutionEngine** | (Phase 0) | Call(callee_name) | 指令级 | 预扫描 |

> * ch09 需要固定点迭代（最多20次模块级遍历），无法合并到单次遍历

### 性能瓶颈量化

假设典型模块：
- 4000 个函数
- 平均每函数 100 条指令 = **400K 总指令**

**当前开销**：
- Phase 0: 1 × 400K = 400K 次指令访问
- Phase 1-11: 11 × 400K = **4.4M 次指令访问**
- Phase 12 (ch09): ~20 × 400K = 8M 次指令访问（固定点）
- **总计**: ~12.8M 次 LLVM API 调用

**理论最优**：
- Merged scan: 1 × 400K = 400K 次指令访问
- ch09 fixed-point: ~8M 次指令访问（保持不变）
- **总计**: ~8.4M 次 LLVM API 调用
- **节省**: 4.4M 次调用 (**34% 减少**)

---

## 🎯 优化方案：事件驱动的统一遍历架构

### 架构选择：Option A（单遍多检测器）

**理由**：
1. ✅ **最大化性能收益** - 从 11N 降到 N+K（K=detector 数量）
2. ✅ **实现简单** - 不需要复杂的依赖图或调度器
3. ✅ **可维护性高** - 统一的入口点，清晰的接口契约
4. ✅ **IR Store 友好** - 可以直接使用预分类的指令桶

### 核心组件设计

#### 1. UnifiedDetectorHub（统一检测器中心）

```zig
// src/semantics/unified_detector_hub.zig

pub const UnifiedDetectorHub = struct {
    // Event-driven detector interfaces
    detectors: struct {
        ch04: Ch04ConversionsDetector,
        ch05: Ch05UninitDetector,
        ch06: Ch06ObrmDetector,
        // ... all 14 detectors
    },

    // Shared context (from IR Store)
    ctx: *DetectorContext,

    /// Process a single instruction — dispatches to all relevant detectors
    pub fn processInstruction(self: *UnifiedDetectorHub, inst: c.LLVMValueRef, opcode: c_uint) !void {
        switch (opcode) {
            c.LLVMBitCast => {
                try self.detectors.ch04.onBitcast(inst);
                try self.detectors.heap_prov.onBitcast(inst);
                try self.detectors.ch09.onBitcast(inst);
            },
            c.LLVMCall, c.LLVMInvoke => {
                const callee_name = self.ctx.ir_store.getCalleeNameByInst(inst);
                try self.detectors.ch04.onCall(inst, callee_name);
                try self.detectors.ch05.onCall(inst, callee_name);
                // ... all call-interested detectors
            },
            c.LLVMLoad => {
                try self.detectors.ch05.onLoad(inst);
                try self.detectors.heap_prov.onLoad(inst);
                try self.detectors.ch09.onLoad(inst);
            },
            // ... other opcodes
        }
    }

    /// Process function-level detection (before instruction loop)
    pub fn processFunction(self: *UnifiedDetectorHub, func: c.LLVMValueRef) !void {
        try self.detectors.param_attr.analyzeParams(func);
    }
};
```

#### 2. Detector 接口标准化

每个 detector 必须实现以下接口之一（或多个）：

```zig
// Standard event-driven interface
pub const DetectorInterface = struct {
    // Instruction-level events
    onCall: ?*const fn (self, inst: c.LLVMValueRef, callee: ?[]const u8) anyerror!void,
    onBitcast: ?*const fn (self, inst: c.LLVMValueRef) anyerror!void,
    onLoad: ?*const fn (self, inst: c.LLVMValueRef) anyerror!void,
    onStore: ?*const fn (self, inst: c.LLVMValueRef) anyerror!void,
    onAlloca: ?*const fn (self, inst: c.LLVMValueRef) anyerror!void,
    onGEP: ?*const fn (self, inst: c.LLVMValueRef) anyerror!void,
    onRet: ?*const fn (self, inst: c.LLVMValueRef) anyerror!void,

    // Function-level events
    onFunctionEnter: ?*const fn (self, func: c.LLVMValueRef) anyerror!void,
    onFunctionExit: ?*const fn (self, func: c.LLVMValueRef) anyerror!void,

    // Module-level events
    onModuleComplete: ?*const fn (self, module: c.LLVMModuleRef) anyerror!void,
};
```

#### 3. IR Store 扩展：语义缓存层

在 `ir_store.zig` 中添加语义缓存：

```zig
// Extension to FunctionIR
pub const SemanticCache = struct {
    // Type inference results (computed once, shared by multiple detectors)
    type_inference: std.AutoHashMap(u64, TypeInfo),

    // Pattern match results
    pattern_matches: std.AutoHashMap(u64, PatternMatch),

    // Cross-function relationships
    caller_callee_map: std.AutoHashMap(u64, []u64),

    // DI metadata cache (expensive LLVM API calls)
    di_type_cache: std.AutoHashMap(u64, []const u8),
};

// New method in ModuleIRStore
pub fn getSemanticCache(self: *ModuleIRStore) *SemanticCache {
    return &self.semantic_cache;
}
```

---

## 📐 实施路线图

### Phase 1: 基础架构搭建（预计 2-3 小时）

1. **创建 `unified_detector_hub.zig`**
   - 定义 DetectorContext 结构体
   - 实现 processInstruction 分发逻辑
   - 添加错误处理和日志记录

2. **定义标准 Detector 接口**
   - 在 `src/semantics/detector_interface.zig` 中定义
   - 为所有 14 个 detector 声明接口签名

### Phase 2: Detector 重构（预计 4-5 小时）

逐个重构每个 detector：

**优先级排序**（按性能影响）：
1. `heap_provenance` - 最复杂，最大收益
2. `ch04_conversions` - BitCast 检测
3. `ch05_uninitialized` - 未初始化内存
4. `ch06_obrm` - 所有权规则
5. 其他 7 个 detector

每个 detector 的重构步骤：
1. 将 `detectFunction()` 拆分为事件处理器
2. 移除内部的 BB/指令遍历循环
3. 通过 DetectorContext 访问共享数据
4. 保持原有的 SRT 写入逻辑不变

### Phase 3: IR Store 集成（预计 2 小时）

1. **扩展 FunctionIR**
   - 添加 SemanticCache 字段
   - 实现 getCalleeName() 的批量缓存版本
   - 添加 getDIType() 方法（带缓存）

2. **修改 collect() 方法**
   - 在单次遍历中填充语义缓存
   - 预计算常用查询结果

### Phase 4: 主流程改造（预计 1 小时）

1. **重写 semantic_resolver_pass.zig 的 run() 方法**
   - 使用 IR Store 替代直接 LLVM API 调用
   - 调用 UnifiedDetectorHub.processInstruction()
   - 保留 ch09 固定点迭代和 lang_detector

2. **保持向后兼容**
   - 保留旧的 detect() 接口（标记为 deprecated）
   - 添加编译期开关控制新旧路径

### Phase 5: 测试与验证（预计 1-2 小时）

1. **单元测试**
   - 每个 detector 的事件驱动版本
   - UnifiedDetectorHub 的分发正确性

2. **集成测试**
   - 完整的 pipeline 运行
   - 与旧版本的输出对比（bit-exact match）

3. **性能基准测试**
   - 测量优化前后的执行时间
   - 验证预期的 30-40% 加速比

---

## 🔧 关键技术细节

### 1. 错误处理策略

采用"最佳努力"模式（与现有代码一致）：

```zig
// 在 UnifiedDetectorHub 中
try self.detectors.ch04.onBitcast(inst) catch |err| {
    log.warn("[UnifiedHub] ch04 failed on bitcast: {any}", .{err});
};
```

### 2. 内存管理

- 所有 detector 的生命周期由 UnifiedDetectorHub 管理
- SemanticCache 在 ModuleIRStore.deinit() 时释放
- 避免在热路径上进行堆分配

### 3. 并发安全

当前 pipeline 是单线程的，无需加锁。
未来如果需要并行化，可以在 detector 粒度加读写锁。

### 4. 可观测性

添加详细的性能计数器：

```zig
pub const HubStats = struct {
    instructions_processed: u64,
    detector_calls: [14]u64,  // 每个 detector 被调用的次数
    cache_hits: u64,
    cache_misses: u64,
};
```

---

## 📈 预期效果

### 性能提升

| 指标 | 优化前 | 优化后 | 提升 |
|------|--------|--------|------|
| LLVM API 调用次数 | 12.8M | 8.4M | **34% ↓** |
| 指令遍历次数 | 12次/function | 1次/function | **92% ↓** |
| 预计执行时间 | ~11.8s | **~7.8s** | **34% ↓** |

### 代码质量改善

- ✅ 消除重复的 BB/指令遍历代码
- ✅ 统一的接口契约，易于添加新 detector
- ✅ 更好的缓存利用，减少冗余计算
- ✅ 更清晰的关注点分离

### 可扩展性提升

- 新增 detector 只需实现接口并注册到 Hub
- 无需修改主遍历循环
- IR Store 缓存自动对所有 detector 生效

---

## ⚠️ 风险与缓解措施

### 风险 1: 功能回归

**缓解**:
- 保留旧代码作为 fallback
- 添加 A/B 对比测试（新旧输出必须完全一致）
- 逐步迁移，每次只重构 1-2 个 detector

### 风险 2: 复杂度增加

**缓解**:
- 清晰的接口文档
- 每个 detector 保持独立可测试
- 使用 Zig 的 comptime 强制接口一致性

### 风险 3: ch09 固定点迭代无法合并

**缓解**:
- ch09 保持独立的固定点迭代（这是固有限制）
- 但其他 11 个 detector 可以完全合并
- ch09 可以利用其他 detector 的结果作为初始标记

---

## 📝 下一步行动

1. ✅ 完成本设计文档
2. ⏭ 创建 `src/semantics/detector_interface.zig`
3. ⏭ 创建 `src/semantics/unified_detector_hub.zig`
4. ⏭ 重构第一个 detector（推荐从 param_attr 开始，最简单）
5. ⏭ 逐步迁移其余 detector
6. ⏭ 集成 IR Store 缓存层
7. ⏭ 性能测试和验证

---

## 附录：Detector 事件订阅表

| Detector | onCall | onBitCast | onLoad | onStore | onAlloca | onGEP | onRet | onFuncEnter |
|----------|--------|-----------|--------|---------|----------|-------|-------|-------------|
| ch04 | ✓ | ✓ | | | | | | |
| ch05 | ✓ | | ✓ | | | | | |
| ch06 | ✓ | | | ✓ | | | | |
| ch08 | ✓ | | | | | | | |
| ch09 | | ✓ | ✓ | | | ✓ | | |
| ch10 | ✓ | | | | | | | |
| posix | ✓ | | | | | | | |
| param_attr | | | | | | | | ✓ |
| heap_prov | ✓ | | ✓ | | ✓ | ✓ | | |
| interior_mut | ✓ | | | | | | | |
| into_raw | ✓ | | | | | | | |
| lib_alloc | ✓ | | | | | | | |
| lang_det | | | | | | | | ✓ |
| ResolutionEng | ✓ | | | | | | | |

这个表格显示了每个 detector 订阅了哪些事件，用于优化分发逻辑。
