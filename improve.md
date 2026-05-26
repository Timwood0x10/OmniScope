现状总结

  你已经搭好了完整的平台基础设施层：

  ┌─────────────────────────────────┬──────────────────────────────────────────────┬──────┐
  │              模块               │                     职责                     │ 状态 │
  ├─────────────────────────────────┼──────────────────────────────────────────────┼──────┤
  │ platform_profile.zig            │ 从 triple/datalayout 检测 OS、格式、arch     │ 完成 │
  ├─────────────────────────────────┼──────────────────────────────────────────────┼──────┤
  │ platform_normalizer.zig         │ 符号规范化解构、调试路径归一化、Section 分类 │ 完成 │
  ├─────────────────────────────────┼──────────────────────────────────────────────┼──────┤
  │ platform_runtime.zig            │ 运行时函数分类（按平台）                     │ 完成 │
  ├─────────────────────────────────┼──────────────────────────────────────────────┼──────┤
  │ surface_classifier/platform.zig │ Platform hint → SurfaceClassifier 集成       │ 完成 │
  └─────────────────────────────────┴──────────────────────────────────────────────┴──────┘

  但集成层还有缺口。目前 platform_profile 只被 surface_classifier_pass 使用，其他 pass 还看不到它。

  你调研结果的核心洞见 → 项目落地

  你的三平台对比表暴露了 5 个具体的落地缺口：

  1. PlatformKind 需要区分 MinGW vs MSVC

  两个都是 .windows，但 ABI 不同：
  - MinGW (x86_64-w64-windows-gnu): 用 GNU 风格 struct passing，函数名 _square
  - MSVC (x86_64-pc-windows-msvc): 用 Microsoft x64 calling convention，函数名 ?square@@YAHH@Z
  
  影响：boundary.zig 的 isUnmangledName() 不能识别 MSVC ? 前缀 mangling

  2. boundary.zig 缺少平台感知

  - isUnmangledName() 只检测 _ZN/_R，漏掉了 MSVC 的 ? mangling
  - isExportSection() 只 handle wasm/ELF，缺少 Mach-O __DATA,__la_symbol_ptr 和 COFF .idata$2/.CRT$XCA
  - Windows dllimport/dllexport 未检测

  3. calling convention 差异未建模

  - SysV AMD64 (Linux): 6 个寄存器传参
  - Microsoft x64 (Windows): 4 个寄存器 + shadow space
  - 影响 ptr_lifetime 中参数的生命周期分析和所有权分析

  4. dso_local/dllimport 语义缺失

  - dso_local 出现在所有平台但含义不同
  - Windows DLL 的导入/导出语义直接影响 FFI boundary 判定

  5. platform_profile 未注入下游 pass

  目前只在 surface_classifier_pass.zig 使用。ffi_language_classifier.zig、ptr_lifetime_violations.zig、issue_suppression.zig 都需要平台上下文。

  ---
  具体实施建议
  
  按优先顺序：

  P0 — 扩展 PlatformKind 加 MinGW/MSVC 子类型
  - 在 PlatformKind 加 windows_gnu / windows_msvc，或增加 abi: WindowsAbi 字段
  - 从 triple 后缀区分 (-gnu → MinGW, -msvc → MSVC)
  - 顺便加 WindowsAbi enum
  
  P1 — boundary.zig 平台感知增强
  - isUnmangledName() 增加 MSVC ? mangling 检测
  - isExportSection() 增加 Mach-O 和 COFF 导出 section 模式
  - 新增 detectDllImportExport() 检查 LLVM DLL storage class
  
  P2 — platform_profile 注入所有需要平台信息的 pass
  - ffi_language_classifier.zig: 传 PlatformProfile，用于 MSVC 符号解码
  - ptr_lifetime_violations.zig: 按平台选择栈布局策略
  - issue_suppression.zig: 使用平台上下文过滤 Windows CRTP 路径
  
  P3 — 增加 Attribute 提取层
  - 解析 frame-pointer、target-features attribute
  - 用于 stack analysis 和 sanitizer detection

  ---
