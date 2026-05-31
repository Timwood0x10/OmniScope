# OmniScope 0.2.0 Code Review 报告 - Part 2: 缺失功能

## ❌ 未完成的工作 (没做啥)

---

### 1. FFI契约数据库 ❌ (0% 完成)

**计划位置**: `src/semantics/resource/contracts.zig` (新建)

**现状**: 
- ❌ 文件不存在
- ✅ 但有相关基础: `src/semantics/resource/contract.zig` (9KB)
  - 已有 `Contract` 类型定义
  - 但不是完整的契约数据库

**缺失内容**:
```zig
// 需要实现:
pub const FFIContractDB = struct {
    contracts: std.StringHashMap(FFIContract),
    
    pub fn init(allocator: std.mem.Allocator) !FFIContractDB;
    pub fn loadBuiltinContracts(self: *FFIContractDB) !void;
    pub fn isValidPair(alloc_func, free_func) ?PairValidity;
    pub fn shouldReportLeak(alloc_func) bool;
};

// 需要内置契约:
- OpenSSL (10+ 函数)
- SQLite (5+ 函数)
- Python C API (15+ 函数)
- JNI (8+ 函数)
- POSIX (10+ 函数)
```

**影响**: 
- ❌ 无法检测错误配对 (如 SSL_CTX_new + BIO_free)
- ❌ 无法抑制 GC 管理的对象泄漏报告
- ❌ TP率提升目标无法达成

---

### 2. MemoryGraph 多语言扩展 ❌ (0% 完成)

**计划**: 在 `AllocNode` 添加 9 个新字段

**现状**: 
```zig
// 当前 AllocNode (简化):
pub const AllocNode = struct {
    id: u64,
    alloc_inst: u64,
    freed: bool,
    source_kind: SourceKind,
    zone: ZoneKind,
    alloc_lang: Language,
    // ... 基础字段
};
```

**缺失字段**:
```zig
// 需要添加:
ownership_model: OwnershipModel = .manual,
raii_cleanup_sites: std.ArrayList(u64),
has_raii_cleanup: bool = false,
refcount_ops: RefCountOps = .{},
is_gc_managed: bool = false,
gc_scope: ?GCScope = null,
has_deferred_cleanup: bool = false,
defer_sites: std.ArrayList(u64),
container_type: ?ContainerType = null,
```

**影响**:
- ❌ 语言适配器无法记录分析结果
- ❌ Python 引用计数追踪无法存储
- ❌ Go defer 清理无法标记
- ❌ Rust RAII 无法追踪

---

### 3. SemanticKind 多语言扩展 ❌ (0% 完成)

**计划**: 添加 16 个新变体

**现状**: 18 个变体 (只覆盖 Rust/Zig)

**缺失变体**:
```zig
// 需要添加:

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
```

**影响**:
- ❌ 语言适配器检测到的模式无法标记
- ❌ 无法区分不同语言的所有权语义

---

### 4. 适配器集成到 PassManager ❌ (0% 完成)

**计划**: 在 PassManager 中调用语言适配器

**现状**: 
- ✅ 适配器代码已写好
- ❌ 但未集成到分析流程

**需要做**:
```zig
// 在 src/pipeline/pipeline.zig 或相关 Pass 中:

const adapter_registry = try AdapterRegistry.init(allocator);
defer adapter_registry.deinit();

// 在分析每个函数时:
for (module_functions) |func| {
    const adapter = adapter_registry.detectAdapter(module);
    const analysis = try adapter.analyzeFunction(func, ctx, allocator);
    
    // 将 analysis 结果应用到 MemoryGraph
    try applyAdapterAnalysis(&memory_graph, analysis);
}
```

**影响**:
- ❌ 语言适配器代码无法运行
- ❌ 所有适配器工作都是"死代码"

---

### 5. 测试套件 ❌ (0% 完成)

**计划**: 
- 单元测试 (语言适配器、契约数据库)
- 集成测试 (端到端)
- 回归测试 (wasmtime, bun)
- 性能测试

**现状**:
```bash
$ ls tests/lang/ 2>/dev/null
# 目录不存在

$ ls tests/resource/ 2>/dev/null
# 目录不存在

$ ls tests/regression/ 2>/dev/null
# 目录不存在
```

**影响**:
- ❌ 无法验证新功能是否工作
- ❌ 无法测量 FP/TP 率改进
- ❌ 无法进行回归测试

---

### 6. CLI 参数集成 ⚠️ (部分完成)

**计划**: 
```bash
--boundary-only
--min-severity high
--suppress-allocator-shims
--suppress-rust-internals
```

**现状**:
- ✅ `boundary_only` 字段存在于 config
- ❌ 未在 CLI 参数解析中实现
- ❌ 未在输出过滤中使用

**需要检查**: `src/main.zig` 的参数解析逻辑

---

### 7. 文档更新 ❌ (0% 完成)

**计划**:
- README 更新 (多语言支持)
- API 参考更新
- 多语言使用指南

**现状**:
- ❌ README 未提及 Python/Go/C++ 适配器
- ❌ 无多语言使用示例
- ❌ API 文档未更新

---

## 📊 缺失功能优先级

| 优先级 | 功能 | 工作量 | 阻塞程度 |
|--------|------|--------|---------|
| **P0** | MemoryGraph 扩展 | 2小时 | 🔴 阻塞所有 |
| **P0** | SemanticKind 扩展 | 1小时 | 🔴 阻塞所有 |
| **P0** | 适配器集成 | 4小时 | 🔴 阻塞运行 |
| **P1** | FFI契约数据库 | 6小时 | 🟡 影响TP率 |
| **P1** | CLI 参数集成 | 2小时 | 🟡 影响体验 |
| **P2** | 测试套件 | 8小时 | 🟢 质量保证 |
| **P2** | 文档更新 | 4小时 | 🟢 用户体验 |

---

## 下一部分预告

Part 3 将给出详细的下一步行动计划。
