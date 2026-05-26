现在 OmniScope 的判定模式是:
  classify_function(callee_name) → language
  if alloc_lang != free_lang: report FP
  
  每加一个语言就要加一套 mangling pattern + 配对规则 + 抑制规则。这是把"语言"当成了一等公民,但语言根本不是真正的语义单位。

  真正的语义单位是"分配族" (allocator family) 和"指针契约" (pointer contract)。

  观察:同样是"Python alloc → Python free",可能跨多个语言名:
  - PyObject_New (Python C API)
  - PyMem_Malloc (Python C API)
  - pymalloc_alloc (CPython 内部)
  
  但它们都是同一个 family — 都使用 CPython 的 small-object allocator。同 family alloc + free 永远不是 bug,与"语言"无关。

  反过来,同语言可能跨 family:
  - malloc(...) + delete[] — 都是 C/C++,但跨 family,是真 bug
  - __rust_alloc + libc::free — 都能编进 Rust 二进制,但跨 family,是真 bug
  
  提议:Allocator Family Graph + 5 个通用模式

  1. AllocatorFamilyRegistry(一张小表,~50 条目)

  Family               | Allocators                   | Deallocators
  ─────────────────────┼──────────────────────────────┼────────────────────
  c_heap               | malloc, calloc, realloc      | free
  cpp_new_scalar       | _Znwm, _Znwj, operator new   | _ZdlPv, delete
  cpp_new_array        | _Znam, _Znaj                 | _ZdaPv, delete[]
  python_object        | PyObject_New, PyObject_NewVar| PyObject_Del, PyObject_Free
  python_mem           | PyMem_Malloc, PyMem_Calloc   | PyMem_Free
  python_mem_raw       | PyMem_RawMalloc              | PyMem_RawFree
  rust_global          | __rust_alloc, alloc_zeroed   | __rust_dealloc
  zig_gpa              | (heap.page_allocator chain)  | (page_allocator.free)
  go_gc                | runtime.mallocgc             | (GC managed)
  java_local_ref       | NewLocalRef                  | DeleteLocalRef
  java_global_ref      | NewGlobalRef                 | DeleteGlobalRef
  csharp_hglobal       | Marshal.AllocHGlobal         | Marshal.FreeHGlobal
  csharp_cotask        | CoTaskMemAlloc               | CoTaskMemFree

  这张表是有限的、稳定的、可枚举的。所有主流语言的 allocator family 加起来不超过 ~50 条。它不是白名单(白名单是"列出 OK 的函数名"),它是结构性事实(每个 alloc 在世界上都对应一个唯一的 free)。

  2. MemoryGraph 节点存 family 而不是 language

  现在你的节点存 alloc_lang: .python,改成 alloc_family: "python_object"。

  释放点的比较从:
  if alloc_lang != free_lang and not allowed_cross_lang(alloc_lang, free_lang):
      report(.cross_language_free)

  变成:
  if alloc_family != free_family:
      report(.cross_family_free)
      
  一行。无 per-language 分支。新语言加入只需要扩 Registry,不需要改 detection 代码。

  3. 5 个跨语言通用模式(替代所有语言特定 suppression)

  ┌─────────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┬──────────────────────────────────────────────────┐
  │          模式           │                                                        通用判定                                                         │                    替代了什么                    │
  ├─────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────┤
  │ 同 family alloc/free    │ family(alloc) == family(free)                                                                                           │ P1 Python pair, P6 cpp new/delete                │
  ├─────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────┤
  │ Destructor 模式         │ callee 是 single-callsite leaf,只调用 free,且其函数名/debug 包含 destructor 标记(drop, D0Ev, dealloc, Dispose, __del__) │ P2 Rust Drop, C++ ~Class(), C# Dispose           │
  ├─────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────┤
  │ Slice-to-ptr bridge     │ callee body 只做 getelementptr + 返回,无 alloc 无 free,签名 (slice/ref) → *T                                            │ P3 as_ptr / as_mut_ptr / ptr_mut_void            │
  ├─────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────┤
  │ Owned reference release │ callee 是 atomic decrement + conditional free 序列                                                                      │ Py_DECREF, Arc::drop, [release] 各种 refcounting │
  ├─────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────┤
  │ Static lifetime sink    │ alloc 结果存入 global/static 后未再被任何 path 释放,且分配只在程序生命周期发生一次                                      │ P7 静态 new[] (cpp_hash::S0)                     │
  └─────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┴──────────────────────────────────────────────────┘

  每个模式的判定都是结构性的(看 IR 的形状),不依赖函数名或语言标签。

  怎么从 IR 不靠名字识别"Destructor 模式"

  举 Rust Drop 的例子。当前判定是"函数名是 _ZN..4drop..E" → 太脆。改成结构性判定:

  1. 函数 F 是 leaf (callee count ≤ 2)
  2. F 的所有调用 except 一个 free 都是纯计算 / log / debug print
  3. F 的唯一参数是 *mut Self (即 self 指针)
  4. F 调用的 free 函数 F_free 的 family 与 alloc family 一致
  5. F 没有任何 escape (无 store-to-global, 无 return ptr)

  满足这 5 条 → 这是 destructor 模式,不报警。无论调用方是 Rust / C++ / Swift / C# — 形状是一样的。

  这样做能解决你的"修修补补"问题吗?

  具体看 P1-P8 怎么塌缩:

  ┌──────────────────────────────┬────────────────────────────────────────────────────────┐
  │            旧任务            │                         新方式                         │
  ├──────────────────────────────┼────────────────────────────────────────────────────────┤
  │ P1 Python C API 所有权未建模 │ 变成 Registry 的 6 条新 entry,无代码改动               │
  ├──────────────────────────────┼────────────────────────────────────────────────────────┤
  │ P2 Rust Drop + C free 配对   │ 变成"Destructor 模式" 1 条结构判定                     │
  ├──────────────────────────────┼────────────────────────────────────────────────────────┤
  │ P3 FFI helper 返回 raw ptr   │ 变成"Slice-to-ptr bridge"模式                          │
  ├──────────────────────────────┼────────────────────────────────────────────────────────┤
  │ P6 _Znam 未注册为 heap       │ 变成 Registry 1 条 entry                               │
  ├──────────────────────────────┼────────────────────────────────────────────────────────┤
  │ P5 Rust stdlib core::* FP    │ 需要单独处理(provenance / debug-path filtering 已经有) │
  ├──────────────────────────────┼────────────────────────────────────────────────────────┤
  │ P4 非指针返回值误判          │ 与 family 无关,独立的 type-guard 修复                  │
  ├──────────────────────────────┼────────────────────────────────────────────────────────┤
  │ P7 静态 new[] 漏检           │ 变成"Static lifetime sink" 模式                        │
  ├──────────────────────────────┼────────────────────────────────────────────────────────┤
  │ P8 Path-sensitive leak       │ 与 family 无关,独立的 path-sensitive engine            │
  └──────────────────────────────┴────────────────────────────────────────────────────────┘

  6/8 任务消解成"扩 Registry / 加结构模式" — 不再是写规则,是给已有引擎喂数据。

  你的语义图就是天然的载体

  我看你的 semantics/ 目录:memory_graph.zig、semantic_tree.zig、call_graph.zig、allocator_kb.zig —— 载体已经具备,缺的是:

  1. allocator_kb.zig 当前内容偏散,做成结构化 Registry(YAML/TOML 配置 + Zig 解析,或纯 Zig const table),把上面那 ~50 条 family 关系填进去
  2. memory_graph.zig 节点的 alloc_lang 字段升级成 alloc_family: FamilyId(language 留作 hint,不参与决策)
  3. ptr_lifetime_violations.zig 中所有 per-language 分支(if free_is_rust and alloc_is_c...)统一为 family_lookup + compare
  4. 抑制层新增 5 个结构模式 detector(destructor_pattern.zig, bridge_helper.zig, refcount_release.zig, ...),取代当前散落在 issue_suppression.zig 里的几十个名字模式

  实施顺序(增量,不大爆破)

  Phase A(1-2 天): 不动检测器,只新增 allocator_family_registry.zig,把现有所有 alloc/free 函数名分桶进 family。先 dry-run,跟现有判定对比,验证 ~50 条 family 是否足够覆盖。

  Phase B: 把 MemoryGraph 节点加一个 family 字段,与现有 alloc_lang 并存。新字段先只用于打 trace,不参与决策。

  Phase C: 在 ptr_lifetime_violations.checkCrossLanguageFree 里加一个优先于现有 per-language 分支的 family check。family 匹配 → 直接 skip,跳过所有后续 per-lang 逻辑。

  Phase D: 替换 5 个语言特定 suppression 规则为结构性模式 detector。每个 detector 不超过 100 行,完全用 IR shape 判定。

  Phase E: 删除 per-language 分支的死代码。
  
  每一步都不破坏现有行为(只新增条件,不删旧条件),最后一步才清理。
