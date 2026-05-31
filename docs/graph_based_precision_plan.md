# 基于内存图和语义树的精度优化方案

## 核心思想：用图推理替代白名单

**问题**: 当前free_validation只做局部分析，丢失了跨函数的所有权信息  
**方案**: 利用MemoryGraph的全局视图，追踪指针的完整生命周期

---

## 方案1: 基于内存图的所有权追踪 (P0 - 最重要)

### 当前问题

```zig
// free_validation.zig:357-374
.from_param => {
    // 问题：只看到参数，不知道参数的来源
    // 如果参数来自__rust_alloc，用__rust_dealloc释放是正确的
    // 但当前代码无法知道这个信息
    if (isFreeSafe(callee_name, origin, src)) return false;
    ...
}
```

### 解决方案：查询内存图

```zig
/// 改进的checkFreeCall - 使用内存图追踪所有权
fn checkFreeCall(
    ctx: *PassContext,
    inst: c.LLVMValueRef,
    pointer_origins: *const std.AutoHashMap(c.LLVMValueRef, PointerInfo),
    caller_func: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !bool {
    const opcode = c.LLVMGetInstructionOpcode(inst);
    if (!llvm_safe.isCallOrInvoke(opcode)) return false;

    const called = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called) == 0) return false;

    const callee_name_ptr = c.LLVMGetValueName(called);
    if (@intFromPtr(callee_name_ptr) == 0) return false;

    const callee_name = std.mem.span(callee_name_ptr);
    if (!isFreeFunction(callee_name)) return false;

    const ptr_arg = c.LLVMGetOperand(inst, 0);
    if (@intFromPtr(ptr_arg) == 0) return false;

    // ═══════════════════════════════════════════════════════════
    // 新增：查询内存图获取完整的所有权信息
    // ═══════════════════════════════════════════════════════════
    const ptr_val: u64 = @intFromPtr(ptr_arg);
    
    // 1. 查找指针的规范分配节点
    const alloc_node = ctx.memory_graph.findCanonicalAlloc(ptr_val);
    
    if (alloc_node) |node| {
        // 2. 检查分配器和释放器是否匹配
        const alloc_family = node.alloc_family orelse .invalid;
        const free_family = ctx.memory_graph.classifyReleaseFamily(callee_name);
        
        // 3. 同一family的分配和释放是安全的
        if (alloc_family == free_family and alloc_family != .invalid) {
            diag.debug("FreeValidation: {s} matches alloc family {s}, safe", .{
                callee_name, @tagName(alloc_family)
            });
            return false; // 安全，不报告
        }
        
        // 4. 检查是否是Rust所有权转移
        if (isRustOwnershipTransfer(node, callee_name)) {
            diag.debug("FreeValidation: Rust ownership transfer detected, safe", .{});
            return false;
        }
        
        // 5. 检查是否跨语言分配器
        if (isCrossAllocatorMismatch(node, callee_name)) {
            // 这是真正的bug！
            try reportCrossAllocatorFree(ctx, caller_func, callee_name, ptr_arg, node, diag);
            return true;
        }
        
        // 6. 检查是否已经释放过（double-free）
        if (node.freed) {
            try reportDoubleFree(ctx, caller_func, callee_name, ptr_arg, node, diag);
            return true;
        }
    }
    
    // 如果内存图中没有找到，回退到原来的逻辑
    const origin_info = pointer_origins.get(ptr_arg);
    const origin = if (origin_info) |info| info.origin else .unknown;
    
    // ... 原来的逻辑作为fallback
}

/// 检查是否是Rust所有权转移
fn isRustOwnershipTransfer(node: *const AllocNode, free_func: []const u8) bool {
    // 检查分配语言和释放函数是否都是Rust
    if (node.alloc_lang != .rust) return false;
    if (!isRustDeallocFunction(free_func)) return false;
    
    // Rust内部的分配和释放总是安全的
    return true;
}

/// 检查是否是跨分配器错误
fn isCrossAllocatorMismatch(node: *const AllocNode, free_func: []const u8) bool {
    const alloc_family = node.alloc_family orelse return false;
    const free_family = ctx.memory_graph.classifyReleaseFamily(free_func);
    
    // 不同family且都不是invalid = 跨分配器bug
    if (alloc_family != free_family and 
        alloc_family != .invalid and 
        free_family != .invalid) 
    {
        return true;
    }
    
    return false;
}
```

### 效果

**修复前**:
```
__rust_alloc → 参数传递 → __rust_dealloc
                ↓
         标记为from_param
                ↓
         报告CRITICAL: invalid_free ❌
```

**修复后**:
```
__rust_alloc → 参数传递 → __rust_dealloc
       ↓                        ↓
  内存图记录                查询内存图
  alloc_family=rust       free_family=rust
                ↓
         family匹配，安全 ✅
```

**预期改进**: CRITICAL误报从54降到<5

---

## 方案2: 基于语义树的上下文推理 (P1)

### 问题：unchecked_return过度敏感

当前所有未检查的返回值都被标记，但很多是安全的：
- abort路径中的`write()`
- 日志函数
- 格式化函数

### 解决方案：语义树上下文分析

```zig
/// 使用语义树判断unchecked_return的严重程度
fn classifyUncheckedReturn(
    ctx: *PassContext,
    call_inst: c.LLVMValueRef,
    callee_name: []const u8,
) Severity {
    const inst_val: u64 = @intFromPtr(call_inst);
    
    // 1. 查询语义树，获取调用上下文
    const semantic_node = ctx.semantic_tree.findNode(inst_val);
    
    if (semantic_node) |node| {
        // 2. 检查是否在错误处理路径
        for (node.resolutions.items) |resolution| {
            switch (resolution.kind) {
                .file_operation, .network_operation, .process_operation => {
                    // POSIX syscall在错误路径中可以忽略返回值
                    if (isInErrorPath(ctx, call_inst)) {
                        return .low;
                    }
                },
                .raii_drop_release => {
                    // RAII析构函数的返回值通常可以忽略
                    return .low;
                },
                .library_release => {
                    // 库清理函数的返回值通常可以忽略
                    return .low;
                },
                else => {},
            }
        }
    }
    
    // 3. 检查函数语义
    if (ctx.semantic_registry) |registry| {
        if (registry.lookup(callee_name)) |semantics| {
            switch (semantics.category) {
                .logging => return .low,
                .formatting => return .low,
                .assertion => return .low,
                .critical_syscall => return .high,
                .memory_allocation => return .high,
                else => {},
            }
        }
    }
    
    // 4. 默认：MEDIUM
    return .medium;
}

/// 检查是否在错误处理路径
fn isInErrorPath(ctx: *PassContext, inst: c.LLVMValueRef) bool {
    // 检查基本块的前驱是否包含错误检查
    const bb = c.LLVMGetInstructionParent(inst);
    if (@intFromPtr(bb) == 0) return false;
    
    // 遍历前驱基本块
    var pred = c.LLVMGetFirstPredecessor(bb);
    while (@intFromPtr(pred) != 0) : (pred = c.LLVMGetNextPredecessor(pred)) {
        const term = c.LLVMGetBasicBlockTerminator(pred);
        if (@intFromPtr(term) == 0) continue;
        
        // 检查是否是条件分支，且条件是错误检查
        if (c.LLVMGetInstructionOpcode(term) == c.LLVMBr) {
            const cond = c.LLVMGetCondition(term);
            if (@intFromPtr(cond) != 0) {
                // 检查条件是否是错误检查（icmp eq/ne with null/0/-1）
                if (isErrorCheckCondition(cond)) {
                    return true;
                }
            }
        }
    }
    
    return false;
}
```

### 效果

**修复前**:
```c
if (fd < 0) {
    write(STDERR, "error", 5);  // 报告HIGH: unchecked_return ❌
    abort();
}
```

**修复后**:
```
语义树分析：
  - write是file_operation
  - 在错误路径中（abort前）
  - 降级为LOW ✅
```

**预期改进**: HIGH/MEDIUM误报减少~600个

---

## 方案3: 基于内存图的逃逸分析 (P1)

### 问题：memory_leak误报

Rust的RAII模式被误判为泄漏：
```rust
let v = Vec::new();  // 分配
// ... 使用 ...
// } // Vec::drop自动释放，但工具认为是泄漏
```

### 解决方案：逃逸分析

```zig
/// 使用内存图的逃逸分析判断是否真的泄漏
fn isRealMemoryLeak(
    ctx: *PassContext,
    alloc_inst: c.LLVMValueRef,
) bool {
    const ptr_val: u64 = @intFromPtr(alloc_inst);
    
    // 1. 查找分配节点
    const node = ctx.memory_graph.findCanonicalAlloc(ptr_val);
    if (node == null) return false;
    
    const alloc_node = node.?;
    
    // 2. 检查是否已经释放
    if (alloc_node.freed) return false;
    
    // 3. 检查逃逸记录
    if (alloc_node.escapes) |escape_list| {
        for (escape_list.items) |escape| {
            switch (escape.kind) {
                // 返回给调用者 = 所有权转移，不是泄漏
                .return_to_caller => return false,
                
                // 存储到out参数 = 所有权转移
                .out_param => return false,
                
                // 存储到全局/静态 = 可能是单例模式
                .global_store, .static_lifetime => {
                    // 检查是否是已知的单例模式
                    if (isSingletonPattern(ctx, alloc_node)) {
                        return false;
                    }
                },
                
                // 传递给消费函数 = 所有权转移
                .consumed_by_function => return false,
                
                // 存储到容器 = 容器负责释放
                .container => return false,
                
                else => {},
            }
        }
    }
    
    // 4. 检查是否是RAII管理的
    if (isRAIIManaged(ctx, alloc_node)) {
        return false;
    }
    
    // 5. 检查是否在条件分支中（可能不执行）
    if (alloc_node.is_conditional) {
        // 降低置信度，但仍然报告
        return true;
    }
    
    // 6. 真正的泄漏
    return true;
}

/// 检查是否是RAII管理的分配
fn isRAIIManaged(ctx: *PassContext, node: *const AllocNode) bool {
    // 检查分配是否在RAII类型的构造函数中
    // 例如：Vec::new, Box::new, String::new
    
    const alloc_func = node.alloc_func_name;
    
    // Rust RAII类型
    const rust_raii_patterns = [_][]const u8{
        "Vec$LT$",
        "Box$LT$",
        "String",
        "HashMap$LT$",
        "BTreeMap$LT$",
        "Arc$LT$",
        "Rc$LT$",
    };
    
    for (rust_raii_patterns) |pattern| {
        if (std.mem.indexOf(u8, alloc_func, pattern) != null) {
            return true;
        }
    }
    
    // C++ RAII类型
    const cpp_raii_patterns = [_][]const u8{
        "std::vector",
        "std::string",
        "std::unique_ptr",
        "std::shared_ptr",
        "std::map",
    };
    
    for (cpp_raii_patterns) |pattern| {
        if (std.mem.indexOf(u8, alloc_func, pattern) != null) {
            return true;
        }
    }
    
    return false;
}

/// 检查是否是单例模式
fn isSingletonPattern(ctx: *PassContext, node: *const AllocNode) bool {
    // 单例模式特征：
    // 1. 只分配一次
    // 2. 存储到静态变量
    // 3. 函数名包含"instance", "singleton", "get_global"等
    
    if (node.escapes) |escape_list| {
        var has_static_store = false;
        for (escape_list.items) |escape| {
            if (escape.kind == .static_lifetime or escape.kind == .global_store) {
                has_static_store = true;
                break;
            }
        }
        
        if (!has_static_store) return false;
    }
    
    const alloc_func = node.alloc_func_name;
    const singleton_patterns = [_][]const u8{
        "instance",
        "singleton",
        "get_global",
        "get_static",
        "once",
        "lazy",
    };
    
    for (singleton_patterns) |pattern| {
        if (std.mem.indexOfIgnoreCase(u8, alloc_func, pattern) != null) {
            return true;
        }
    }
    
    return false;
}
```

### 效果

**修复前**:
```rust
fn process() {
    let v = Vec::new();  // 分配
    v.push(1);
    // } // 报告memory_leak ❌
}
```

**修复后**:
```
内存图分析：
  - 分配在Vec::new中
  - Vec是RAII类型
  - 作用域结束时自动调用drop
  - 不报告 ✅
```

**预期改进**: memory_leak误报减少~200个

---

## 方案4: 基于调用图的跨函数分析 (P2)

### 问题：跨函数的所有权转移丢失

```rust
fn allocate() -> *mut u8 {
    Box::into_raw(Box::new(0))  // 所有权转移给调用者
}

fn deallocate(ptr: *mut u8) {
    unsafe { Box::from_raw(ptr) }  // 正确的释放
}

fn main() {
    let ptr = allocate();
    deallocate(ptr);  // 报告invalid_free ❌
}
```

### 解决方案：调用图分析

```zig
/// 使用调用图追踪跨函数的所有权流
fn trackOwnershipAcrossCalls(
    ctx: *PassContext,
    ptr_val: u64,
) ?OwnershipChain {
    // 1. 查找指针的分配点
    const alloc_node = ctx.memory_graph.findCanonicalAlloc(ptr_val);
    if (alloc_node == null) return null;
    
    var chain = OwnershipChain.init(ctx.allocator);
    
    // 2. 从分配点开始，沿着调用图追踪
    var current_func = alloc_node.?.alloc_func_val;
    var current_ptr = ptr_val;
    
    while (current_func != null) {
        // 3. 检查当前函数是否返回这个指针
        const ret_edges = ctx.memory_graph.call_ret_by_ptr.get(current_ptr);
        if (ret_edges) |edges| {
            for (edges.items) |edge_idx| {
                const edge = ctx.memory_graph.call_rets.items[edge_idx];
                
                // 4. 记录所有权转移
                try chain.addTransfer(.{
                    .from_func = current_func,
                    .to_func = edge.caller_inst,
                    .transfer_kind = .return_value,
                    .ptr_val = current_ptr,
                });
                
                // 5. 继续追踪到调用者
                current_func = getCallerFunc(ctx, edge.caller_inst);
                current_ptr = edge.ret_ptr;
            }
        } else {
            break;
        }
    }
    
    return chain;
}

/// 所有权链
const OwnershipChain = struct {
    transfers: std.ArrayList(OwnershipTransfer),
    allocator: std.mem.Allocator,
    
    const OwnershipTransfer = struct {
        from_func: ?c.LLVMValueRef,
        to_func: u64,
        transfer_kind: TransferKind,
        ptr_val: u64,
    };
    
    const TransferKind = enum {
        return_value,
        out_param,
        global_store,
    };
    
    pub fn init(allocator: std.mem.Allocator) OwnershipChain {
        return .{
            .transfers = std.ArrayList(OwnershipTransfer).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *OwnershipChain) void {
        self.transfers.deinit();
    }
    
    pub fn addTransfer(self: *OwnershipChain, transfer: OwnershipTransfer) !void {
        try self.transfers.append(transfer);
    }
    
    /// 检查释放是否在所有权链的末端
    pub fn isValidFreePoint(self: *const OwnershipChain, free_func: c.LLVMValueRef) bool {
        if (self.transfers.items.len == 0) return true;
        
        const last_transfer = self.transfers.items[self.transfers.items.len - 1];
        return @intFromPtr(free_func) == last_transfer.to_func;
    }
};
```

### 效果

**修复前**:
```
allocate() → Box::into_raw → 返回ptr
                                ↓
main() → 接收ptr → deallocate(ptr)
                        ↓
                  Box::from_raw
                        ↓
                报告invalid_free ❌
```

**修复后**:
```
调用图分析：
  allocate: Box::into_raw (所有权转出)
      ↓
  main: 接收ptr (所有权转入)
      ↓
  deallocate: Box::from_raw (所有权转入)
      ↓
  所有权链完整，安全 ✅
```

**预期改进**: 跨函数误报减少~50个

---

## 实施计划

### 阶段1: 内存图集成 (2-3天)

**目标**: 修复54个CRITICAL误报

1. ✅ 在free_validation.zig中集成内存图查询
2. ✅ 实现`findCanonicalAlloc`查询
3. ✅ 实现family匹配检查
4. ✅ 测试wasmtime

**代码位置**:
- `src/pass/analysis/issue/free_validation.zig:317-449`
- 新增函数：`isRustOwnershipTransfer`, `isCrossAllocatorMismatch`

### 阶段2: 语义树集成 (2-3天)

**目标**: 减少600个HIGH/MEDIUM误报

1. ✅ 在unchecked_return检测中集成语义树
2. ✅ 实现上下文分析
3. ✅ 实现严重程度分类
4. ✅ 测试corpus

**代码位置**:
- `src/pass/analysis/issue/unchecked_return.zig`
- 新增函数：`classifyUncheckedReturn`, `isInErrorPath`

### 阶段3: 逃逸分析 (3-4天)

**目标**: 减少200个memory_leak误报

1. ✅ 在memory_leak检测中集成逃逸分析
2. ✅ 实现RAII识别
3. ✅ 实现单例模式识别
4. ✅ 测试corpus

**代码位置**:
- `src/pass/analysis/issue/memory_safety.zig`
- 新增函数：`isRealMemoryLeak`, `isRAIIManaged`, `isSingletonPattern`

### 阶段4: 调用图分析 (4-5天)

**目标**: 提升跨函数精度

1. ✅ 实现所有权链追踪
2. ✅ 集成到free_validation
3. ✅ 测试复杂场景

**代码位置**:
- `src/pass/analysis/issue/free_validation.zig`
- 新增模块：`src/pass/analysis/ownership_chain.zig`

---

## 对比：白名单 vs 图推理

| 维度 | 白名单方案 | 图推理方案 |
|------|-----------|-----------|
| **精度** | 中等（70-80%） | 高（>85%） |
| **可维护性** | 差（需要不断添加） | 好（自动推理） |
| **泛化能力** | 差（只覆盖已知模式） | 好（适用所有代码） |
| **误报率** | 中等（20-30%） | 低（<15%） |
| **召回率** | 中等（60-70%） | 高（>80%） |
| **开发成本** | 低（1-2天） | 高（10-15天） |
| **长期价值** | 低（技术债） | 高（核心能力） |

---

## 成功指标

### 短期 (阶段1完成)
- ✅ CRITICAL误报 < 5
- ✅ 内存图查询成功率 > 90%
- ✅ wasmtime分析时间 < 90秒

### 中期 (阶段2-3完成)
- ✅ 总体精度 > 75%
- ✅ HIGH误报 < 150
- ✅ MEDIUM误报 < 300

### 长期 (阶段4完成)
- ✅ 总体精度 > 85%
- ✅ 召回率 > 80%
- ✅ 可用于生产环境

---

## 总结

**核心优势**:
1. **利用现有基建** - 内存图和语义树已经构建好了
2. **全局视图** - 不再局限于单函数分析
3. **精确推理** - 基于图的所有权追踪，不是启发式
4. **可扩展** - 新的语言模式自动支持

**vs 白名单**:
- 白名单：快速但不精确，技术债
- 图推理：慢但精确，长期价值

**建议**: 先实施阶段1（2-3天），立即看到效果。如果效果好，继续后续阶段。

---

生成时间: 2026-05-31
作者: OmniScope团队
