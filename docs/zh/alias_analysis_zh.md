# Alias Analysis Pass (别名分析)

## 概述

基于类型的别名分析（TBAA），检测指针别名关系。快速实用，覆盖80%的场景。

## 位置

```text
src/pass/analysis/alias.zig
```

## AliasPass

```zig
pub const AliasPass = struct {
    pub const name = "alias";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg" };

    ctx: *PassContext,
    diag: *DiagnosticWriter,
    store: *FactStore,
    query: QueryEngine,
    type_cache: std.AutoHashMap(c.LLVMTypeRef, u32),
    ptr_info_map: std.AutoHashMap(c.LLVMValueRef, PointerInfo),
    func_id: u32,
};
```

### 方法

- **init()** - 初始化
- **deinit()** - 清理资源
- **run(ctx, diag)** - 运行分析

## PointerInfo

```zig
const PointerInfo = struct {
    value: c.LLVMValueRef,
    type_id: u32,
    inst_id: u32,
};
```

## 分析策略

1. **类型分组**: 按类型分组指针
2. **局部流不敏感**: 不考虑控制流
3. **堆对象合并**: 合并堆分配对象

## 别名关系

- **alias_may**: 可能别名（同类型）
- **alias_must**: 必须别名（同基指针）

## 使用示例

```zig
var alias_pass = AliasPass.init(allocator, &store);
defer alias_pass.deinit(allocator);

try alias_pass.run(ctx, diag);
```

## 注意事项

- 依赖 cfg 和 dfg Pass
- 简化实现：相同类型可能别名
- 快速但不够精确
