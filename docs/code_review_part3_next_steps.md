# OmniScope 0.2.0 Code Review 报告 - Part 3: 下一步行动

## 🎯 下一步做啥 (优先级排序)

---

## 阶段 1: 核心集成 (1-2天，P0)

### 任务 1.1: 扩展 MemoryGraph 类型 ⏱️ 2小时

**文件**: `src/types/memory_graph_types.zig`

**操作**: 在 `AllocNode` 结构体末尾添加新字段

```zig
// 在 AllocNode 的现有字段后添加:

// ── v0.2.0: 多语言生命周期追踪 ──

/// 所有权模型类型
ownership_model: OwnershipModel = .manual,

/// RAII清理站点
raii_cleanup_sites: std.ArrayList(u64),
has_raii_cleanup: bool = false,

/// 引用计数追踪
refcount_ops: RefCountOps = .{},

/// GC管理标记
is_gc_managed: bool = false,
gc_scope: ?GCScope = null,

/// 延迟清理
has_deferred_cleanup: bool = false,
defer_sites: std.ArrayList(u64),

/// 容器类型推断
container_type: ?ContainerType = null,
```

**同时添加新类型定义**:
```zig
pub const OwnershipModel = enum(u8) {
    manual, raii, refcount, gc, hybrid,
};

pub const RefCountOps = struct {
    increments: u32 = 0,
    decrements: u32 = 0,
    pub fn netCount(self: RefCountOps) i32 { ... }
};

pub const GCScope = enum(u8) {
    local, global, weak,
};

pub const ContainerType = enum(u8) {
    rust_box, rust_vec, rust_string,
    cpp_unique_ptr, cpp_shared_ptr,
    python_list, go_slice,
    // ... 其他
};
```

**验证**: 
```bash
zig build
# 应该编译通过
```

---

### 任务 1.2: 扩展 SemanticKind 枚举 ⏱️ 1小时

**文件**: `src/semantics/semantic_tree.zig`

**操作**: 在 `SemanticKind` 枚举末尾添加

```zig
pub const SemanticKind = enum(u8) {
    // ... 现有 18 个变体 ...
    
    // ── v0.2.0: 多语言支持 ──
    
    // Python (5个)
    python_refcount_inc,
    python_refcount_dec,
    python_borrowed_ref,
    python_owned_ref,
    python_gil_protected,
    
    // Go (4个)
    go_defer_cleanup,
    go_finalizer,
    go_cgo_wrapper,
    go_runtime_alloc,
    
    // C# (3个)
    csharp_safe_handle,
    csharp_finalizer,
    csharp_pinvoke_marshal,
    
    // Java (3个)
    java_local_ref,
    java_global_ref,
    java_weak_ref,
    
    // C++ (4个)
    cpp_unique_ptr,
    cpp_shared_ptr,
    cpp_destructor,
    cpp_exception_path,
};
```

**验证**:
```bash
zig build
# 检查是否有编译错误
```

---

### 任务 1.3: 集成适配器到分析流程 ⏱️ 4小时

**目标**: 让语言适配器真正运行起来

**步骤 A**: 找到主分析入口

```bash
# 查找 PassManager 或主分析循环
grep -r "PassManager\|analyzeModule" src/pipeline/
```

**步骤 B**: 在合适位置添加适配器调用

```zig
// 在 src/pipeline/pipeline.zig 或类似文件中:

const adapter_registry = @import("../lang/adapter_registry.zig");

// 在分析开始时初始化
var registry = try adapter_registry.AdapterRegistry.init(allocator);
defer registry.deinit();

// 在分析每个函数时:
for (functions) |func| {
    // 检测语言
    const adapter = registry.detectAdapter(module) orelse continue;
    
    // 运行适配器分析
    var analysis = try adapter.analyzeFunction(func, ctx, allocator);
    defer analysis.deinit(allocator);
    
    // 应用结果到 MemoryGraph
    for (analysis.allocations.items) |alloc_info| {
        if (memory_graph.findCanonicalAlloc(alloc_info.ptr_val)) |node| {
            node.ownership_model = alloc_info.ownership_model;
            node.is_gc_managed = alloc_info.is_gc_managed;
            // ... 更新其他字段
        }
    }
}
```

**验证**:
```bash
zig build
./zig-out/bin/OmniScope corpus/real_project_test/bun_alloc.bc --json
# 检查是否有适配器相关的日志输出
```

---

## 阶段 2: 功能增强 (2-3天，P1)

### 任务 2.1: 实现 FFI契约数据库 ⏱️ 6小时

**文件**: `src/semantics/resource/contracts.zig` (新建)

**操作**: 复制 Part 2 文档中的完整实现

**关键点**:
1. 定义 `FFIContract` 和 `FFIContractDB` 结构
2. 实现 `loadBuiltinContracts()` - 至少50个契约
3. 实现 `isValidPair()` 和 `shouldReportLeak()`
4. 集成到 `free_validation.zig`

**验证**:
```bash
zig build test -Dtest-filter="ffi_contract"
```

---

### 任务 2.2: 集成 Allocator Shim 检测器 ⏱️ 2小时

**文件**: `src/semantics/free_validation.zig` (修改)

**操作**: 在报告泄漏前检查

```zig
const allocator_shim = @import("../detectors/allocator_shim.zig");

// 在 validateFreeWithMemoryGraph 中:
if (alloc_func_name) |func_name| {
    // 检查是否是 allocator shim
    const shim_result = allocator_shim.AllocatorShimDetector.isAllocatorShim(
        func_name,
        .{ .is_in_global_alloc_impl = true }
    );
    
    if (shim_result == .confirmed_shim or shim_result == .likely_shim) {
        // 抑制报告
        return;
    }
}
```

**验证**:
```bash
./zig-out/bin/OmniScope corpus/real_project_test/bun_alloc.bc --json
# 预期: 19个FP消失
```

---

### 任务 2.3: 激活 Rust 内部函数白名单 ⏱️ 1小时

**操作 A**: 重命名文件
```bash
cd src/whitelists/
mv rust_internal.zig.bak rust_internal.zig
```

**操作 B**: 集成到相关 Pass
```zig
const rust_whitelist = @import("../whitelists/rust_internal.zig");

// 在报告 unchecked_return 前:
if (rust_whitelist.RustInternalWhitelist.shouldSuppress(func_name)) {
    return;  // 抑制报告
}
```

**验证**:
```bash
./zig-out/bin/OmniScope corpus/real_project_test/bun_core.bc --json
# 预期: 13个panic相关FP消失
```

---

### 任务 2.4: 实现 CLI 参数 ⏱️ 2小时

**文件**: `src/main.zig` (修改)

**操作**: 添加参数解析

```zig
// 在参数解析部分:
if (std.mem.eql(u8, arg, "--boundary-only")) {
    config.boundary_only = true;
    continue;
}

if (std.mem.eql(u8, arg, "--min-severity")) {
    i += 1;
    const sev_str = args[i];
    config.min_severity = Severity.parse(sev_str) orelse .low;
    continue;
}
```

**验证**:
```bash
./zig-out/bin/OmniScope --help
# 应该显示新参数

./zig-out/bin/OmniScope corpus/wasmtime_test.bc --boundary-only
# 应该只显示 boundary 问题
```

---

## 阶段 3: 测试与验证 (2-3天，P2)

### 任务 3.1: 创建单元测试 ⏱️ 4小时

**创建目录结构**:
```bash
mkdir -p tests/lang
mkdir -p tests/resource
mkdir -p tests/detectors
mkdir -p tests/whitelists
```

**编写测试** (参考 Part 7 文档):
- `tests/lang/python_adapter_test.zig`
- `tests/lang/go_adapter_test.zig`
- `tests/resource/contracts_test.zig`
- `tests/detectors/allocator_shim_test.zig`

**运行**:
```bash
zig build test
```

---

### 任务 3.2: 回归测试 ⏱️ 2小时

**创建脚本**: `scripts/run_regression.sh`

```bash
#!/bin/bash
echo "=== Regression Test Suite ==="

# Test 1: bun_alloc (应该只有1个issue)
./zig-out/bin/OmniScope corpus/real_project_test/bun_alloc.bc --json > /tmp/bun_alloc.json
issues=$(jq '.summary.total_issues' /tmp/bun_alloc.json)
echo "bun_alloc: $issues issues (expected: 1)"

# Test 2: wasmtime (应该有1个CRITICAL)
./zig-out/bin/OmniScope corpus/wasmtime_test.bc --boundary-only --json > /tmp/wasmtime.json
critical=$(jq '.summary.critical_count' /tmp/wasmtime.json)
echo "wasmtime: $critical critical (expected: 1)"
```

**运行**:
```bash
chmod +x scripts/run_regression.sh
./scripts/run_regression.sh
```

---

### 任务 3.3: 性能测试 ⏱️ 2小时

**测试大文件**:
```bash
time ./zig-out/bin/OmniScope corpus/sqlite3.bc --json
# 目标: <15秒 (3346 functions)

time ./zig-out/bin/OmniScope corpus/curl8.bc --json
# 目标: <5秒 (1245 functions)
```

---

## 📅 时间估算

| 阶段 | 任务数 | 总时间 | 优先级 |
|------|--------|--------|--------|
| **阶段1: 核心集成** | 3 | 7小时 | P0 🔴 |
| **阶段2: 功能增强** | 4 | 11小时 | P1 🟡 |
| **阶段3: 测试验证** | 3 | 8小时 | P2 🟢 |
| **总计** | 10 | **26小时** | **3-4天** |

---

## 🎯 最小可行版本 (MVP)

如果时间紧张，**只做阶段1**即可发布 alpha 版本:

**MVP 包含**:
- ✅ MemoryGraph 扩展
- ✅ SemanticKind 扩展
- ✅ 适配器集成
- ✅ Allocator Shim 集成
- ✅ Rust 白名单激活

**MVP 效果**:
- FP率: 96.5% → ~40% (预估)
- 语言适配器可运行
- 基本可用

**后续迭代**:
- Beta 1: 添加 FFI契约数据库
- Beta 2: 完善测试
- Release: 完整文档

---

## 🚀 立即开始

**第一步** (现在就做):
```bash
cd /Users/scc/code/zigcode/OmniScope
git checkout -b feature/v0.2.0-integration

# 任务 1.1: 扩展 MemoryGraph
vim src/types/memory_graph_types.zig
# 添加新字段和类型定义

zig build
# 验证编译通过
```

**预计今天完成**: 任务 1.1 + 1.2 (3小时)
**预计明天完成**: 任务 1.3 (4小时)
**预计后天完成**: 阶段2 (11小时)

---

## ✅ 总结

**已完成**: 60-70% (适配器代码、检测器、白名单)
**待完成**: 30-40% (集成、测试、文档)
**关键路径**: 阶段1 核心集成 (7小时)
**预计发布**: 3-4天后可发布 alpha 版本

**建议**: 先完成阶段1，立即测试效果，再决定是否继续阶段2/3。
