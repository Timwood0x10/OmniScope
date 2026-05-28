# LLVM IR 模式分析报告

**分析日期**: 2026-05-28  
**分析范围**: 本机所有 .ll 文件 (145 个)  
**工具版本**: OmniScope v0.1.8, LLVM 22  

---

## 一、文件分布

| 项目 | 文件数 | 语言 | 说明 |
|------|--------|------|------|
| OmniScope corpus | 37 | C/Rust/Go/Zig | 测试用例和真实项目 |
| ffi-demo | 18 | C/C++/Rust/Zig | FFI 演示项目 |
| researcher/tinygo | 49 | Go | TinyGo 编译器测试 |
| researcher/swift | 19 | Swift | Swift 编译器测试 |
| rustcode/OmniScope-rs | 9 | Rust | OmniScope Rust 版本 |
| rustcode/coq-of-rust | 11 | Rust | Coq 形式化验证 |
| 其他 | 2 | Rust | 杂项 |

---

## 二、关键 IR 模式发现

### 2.1 Rust 的 `UnsafeCell` 模式

**文件**: `bun_alloc.ll`, `blst.ll`, `ripgrep141.ll`

**IR 特征**:
```llvm
%"core::cell::UnsafeCell<core::sync::atomic::private::Align8<usize>>" = type { %"core::sync::atomic::private::Align8<usize>" }
%"core::cell::UnsafeCell<core::mem::maybe_uninit::MaybeUninit<...>>" = type { ... }
```

**规律**:
- Rust 的 `UnsafeCell<T>` 在 IR 中是一个 wrapper struct，包含内部类型
- `Cell`, `RefCell`, `Mutex`, `RwLock`, `Atomic*` 都基于 `UnsafeCell`
- 写入 `UnsafeCell` 内部是合法的 interior mutability，不是 bug
- **当前 OmniScope 无法区分 `UnsafeCell` 写入和普通 `&T` 写入**

### 2.2 Rust 的 `readonly` 属性

**文件**: `bun_alloc.ll`, `ripgrep141.ll`

**IR 特征**:
```llvm
define { ptr, i64 } @_RNvCs9SN9c7tmF9T_9bun_alloc12default_dupe(ptr noalias noundef nonnull readonly captures(none) %src.0, i64 noundef %src.1)
```

**规律**:
- `readonly` 参数 = Rust 的 `&T` (共享引用)
- 无 `readonly` 参数 = Rust 的 `&mut T` (可变引用)
- `noalias` 参数 = Rust 的 `&mut T` (独占引用)
- `captures(none)` = 闭包不捕获环境
- **关键**: 如果参数有 `readonly`，写入它是 UB；如果没有，写入是合法的

### 2.3 Rust 的 `insertvalue`/`extractvalue` 模式

**文件**: `bun_alloc.ll`

**IR 特征**:
```llvm
%2 = insertvalue { i64, ptr } poison, i64 %., 0
%3 = insertvalue { i64, ptr } %2, ptr %new_ptr, 1
ret { i64, ptr } %3
```

**规律**:
- Rust 函数返回 `Result`, `Option`, 元组等类型时，使用 `insertvalue` 构造聚合值
- `extractvalue` 从聚合值中提取字段
- **当前 SRT 的 forward propagation 需要处理这些指令**

### 2.4 C 的 `alloca` + `store`/`load` 模式

**文件**: `rust_ffi_bugs.ll`, `sqlite_binding.ll`, `cross_lang_free_bugs.ll`

**IR 特征**:
```llvm
%ptr = alloca ptr, align 8
%call = call ptr @malloc(i64 noundef 128)
store ptr %call, ptr %ptr, align 8
%0 = load ptr, ptr %ptr, align 8
call void @free(ptr noundef %0)
```

**规律**:
- C 代码使用 `alloca` 分配栈空间，`store`/`load` 访问
- `malloc`/`free` 用于堆分配
- **SRoA 优化后，`alloca` 可能被消除，直接使用 SSA 值**

### 2.5 Rust 的 RAII Drop 模式

**文件**: `bun_alloc.ll`

**IR 特征**:
```llvm
; call <std::sys::pal::unix::sync::mutex::Mutex as core::ops::drop::Drop>::drop
tail call void @_RNvXs2_...Drop4drop(ptr noundef nonnull align 8 %0) #33
; call __rustc::__rust_dealloc
tail call void @_RNvCs3TqXShXgh4d_7___rustc14___rust_dealloc(ptr noundef nonnull %0, i64 noundef 64, i64 noundef 8) #33
```

**规律**:
- Rust 的 `Drop::drop` 实现通常调用 `__rust_dealloc`
- 这是编译器插入的 RAII 释放，不是 bug
- **当前 OmniScope 已部分识别，但需要更完整的 Drop 链追踪**

### 2.6 Go 的 CGo FFI 模式

**文件**: `go-sqlite3.ll`

**IR 特征**:
```llvm
; 类似 C 的模式，但有 Go runtime 调用
call void @runtime.some_function(...)
```

**规律**:
- Go CGo 生成的 IR 类似 C
- 但有 Go runtime 的特殊调用（goroutine, GC 等）
- **需要区分 Go runtime 调用和用户代码**

---

## 三、FP 分类分析

### 3.1 `write_to_immutable` (1877 个 FP)

**根因**: OmniScope 检测所有通过 struct field pointer 的写入，但无法区分：
- `&mut T` 的写入 (合法)
- `&T` + `UnsafeCell` 的写入 (合法)
- `&T` 无 `UnsafeCell` 的写入 (真正的 bug)

**IR 模式**:
```llvm
%field_ptr = getelementptr inbounds %Struct, ptr %base, i32 0, i32 1
%value = load ptr, ptr %field_ptr
store i32 42, ptr %value  ; 这可能是 &mut T 的写入
```

**解决方案**:
1. 检查 `store` 目标的来源是否是 `readonly` 参数
2. 检查类型定义是否包含 `UnsafeCell`
3. 如果两者都不是，才是真正的 bug

### 3.2 `borrow_escape` (71 个 FP)

**根因**: SRoA 优化后，堆指针看起来像栈指针

**IR 模式**:
```llvm
%result = call ptr @malloc(i64 128)
; ... 经过 phi, insertvalue, extractvalue 等操作 ...
call void @some_ffi_function(ptr %result)  ; 看起来像栈指针
```

**解决方案**:
1. Forward propagation: 从 malloc 调用追踪到 FFI 调用
2. 跨函数边界: 通过 return value 和 call argument 传播
3. 处理 `insertvalue`/`extractvalue`/`phi` 指令

### 3.3 `cross_language_free` (4 个 FP)

**根因**: Rust 的 `Box::into_raw()` 返回的指针可以被 C `free()` 释放

**IR 模式**:
```llvm
%raw = call ptr @Box_into_raw(ptr %box)
call void @free(ptr %raw)  ; 这是合法的！
```

**解决方案**:
- 识别 `into_raw` 模式: 返回的指针所有权转移给调用者
- C `free` 可以释放 Rust `Box::into_raw` 返回的指针

### 3.4 `use_after_free` (3 个 FP)

**根因**: 编译器插入的 Drop 释放被误认为是 use-after-free

**解决方案**:
- 识别 RAII Drop 模式
- 如果释放来自 Drop 实现，跳过

---

## 四、语义树增强方案

### 4.1 新增 SemanticKind

```zig
pub const SemanticKind = enum(u8) {
    // 现有的...
    
    // 新增
    interior_mutability,  // UnsafeCell/Cell/RefCell/Mutex/RwLock
    readonly_param,       // &T (共享引用)
    mutable_param,        // &mut T (可变引用)
    raii_drop,            // 编译器插入的 Drop
    into_raw_transfer,    // Box::into_raw 所有权转移
};
```

### 4.2 IR 属性检查

```zig
fn hasReadonlyAttribute(param: LLVMValueRef) bool {
    // 检查参数是否有 readonly 属性
    return LLVMHasAttributeAtIndex(func, param_index, "readonly");
}

fn hasNoaliasAttribute(param: LLVMValueRef) bool {
    // 检查参数是否有 noalias 属性
    return LLVMHasAttributeAtIndex(func, param_index, "noalias");
}
```

### 4.3 类型级 UnsafeCell 检测

```zig
fn typeContainsUnsafeCell(ty: LLVMTypeRef) bool {
    // 检查类型定义是否包含 UnsafeCell
    // 方法: 搜索类型名称中的 "UnsafeCell"
    const name = LLVMGetTypeByName(ctx, "UnsafeCell");
    return name != null;
}
```

### 4.4 Forward Propagation 增强

需要处理的指令:
- `insertvalue`: 构造聚合值
- `extractvalue`: 提取聚合值
- `phi`: 控制流合并
- `select`: 条件选择
- `bitcast`: 类型转换
- `getelementptr`: 指针偏移

---

## 五、最少白名单方案

### 5.1 可接受的白名单

| 函数名 | 语言 | 原因 | 置信度 |
|--------|------|------|--------|
| `malloc_set_zone_name` | C/macOS | 复制字符串，不保留指针 | 高 |
| `Box::into_raw` | Rust | 所有权转移 | 高 |
| `String::into_raw` | Rust | 所有权转移 | 高 |

### 5.2 文档要求

每个白名单项必须包含:
1. 函数名和所在文件
2. 语言和项目
3. 为什么是 FP
4. IR 模式示例
5. 置信度评估

---

## 六、输出格式要求

### 6.1 高置信度 Bug 输出

```
[BUG] cross_language_free
  置信度: HIGH (95%)
  函数: rust_01_alloc_c_free
  文件: corpus/red_team_test/rust_ffi_bugs.ll:36
  
  调用链:
    1. @_RZN4alloc5alloc17h_allocate(i64 128)  ; Rust alloc
    2. %call = call ptr @_RZN4alloc5alloc17h_allocate(...)
    3. store ptr %call, ptr %ptr
    4. %0 = load ptr, ptr %ptr
    5. call void @free(ptr %0)  ; C free ← BUG
  
  证据:
    - 分配器: __rust_alloc (Rust)
    - 释放器: free (C)
    - 分配器和释放器语言不匹配
```

### 6.2 FP 抑制日志

```
[SUPPRESS] write_to_immutable
  函数: some_function
  文件: bun_bundler.ll:1234
  
  原因: store 目标来自 non-readonly 参数 (&mut T)
  证据: param #2 无 readonly 属性
```

---

## 七、实施优先级

1. **P0**: 实现 `readonly` 属性检查 → 抑制 `write_to_immutable` FP
2. **P1**: 实现 `UnsafeCell` 类型检测 → 进一步抑制 `write_to_immutable`
3. **P2**: 增强 forward propagation → 抑制 `borrow_escape` FP
4. **P3**: 识别 `into_raw` 模式 → 抑制 `cross_language_free` FP
5. **P4**: 识别 RAII Drop 模式 → 抑制 `use_after_free` FP

---

## 八、预期效果

| 问题类型 | 当前 FP | 预期 FP | 降幅 |
|----------|---------|---------|------|
| write_to_immutable | 1877 | <100 | 95% |
| borrow_escape | 71 | <10 | 86% |
| cross_language_free | 4 | 0 | 100% |
| use_after_free | 3 | 0 | 100% |
| **总计** | **1966** | **<110** | **94%** |

---

## 九、下一步

1. 实现 `readonly` 属性检查
2. 实现 `UnsafeCell` 类型检测
3. 增强 forward propagation (处理 `insertvalue`/`extractvalue`)
4. 运行全量 bun 分析验证效果
5. 更新文档和测试用例
