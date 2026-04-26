## Wasmtime 源码验证报告

### 一、已验证的源码事实

OminiScpe 检测报告 [wasmtime.md](./wasmtime_source.md)

#### 1. fiber_start 忽略 array_call 返回值

**源码位置**: `crates/wasmtime/src/runtime/vm/stack_switching/stack/unix.rs:298-338`

**事实1**: array_call 返回值语义
- 源码定义：`VMArrayCallNative` 返回 `bool`
- 注释明确：`Returns whether a trap was recorded in TLS for raising`
- `true` = 成功，`false` = 失败并记录 trap

**事实2**: fiber_start 忽略返回值
```rust
// 第326-328行
// TODO(dhil): we are ignoring the boolean return value
// here... we probably shouldn't.
VMFuncRef::array_call(func_ref, None, caller_vmxtx, params_and_returns);
```
- 开发者已用 TODO 注释标记此问题
- 返回值被完全忽略

**事实3**: args.length 无条件更新
```rust
// 第333行
args.length = return_value_count;
```
- 无论 array_call 成功或失败，都无条件设置 length
- 没有检查返回值来决定是否更新

---

#### 2. occupy_next_slots 缺少容量检查

**源码位置**: `crates/cranelift/src/func_environ/stack_switching/instructions.rs:301-320`

**事实4**: occupy_next_slots 直接增加 length
```rust
pub fn occupy_next_slots<'a>(
    &self,
    env: &mut crate::func_environ::FuncEnvironment<'a>,
    builder: &mut FunctionBuilder,
    arg_count: i32,
) -> ir::Value {
    let data = self.get_data(env, builder);
    let original_length = self.get_length(env, builder);
    let new_length = builder
        .ins()
        .iadd_imm(original_length, i64::from(arg_count));
    self.set_length(env, builder, new_length);  // 无容量检查
    // ...
}
```
- 直接计算 `new_length = original_length + arg_count`
- 直接设置 length，未检查是否超过 capacity

**事实5**: 注释与实现不符
```rust
// 第885-887行
// This also checks that the buffer is large enough to hold
// `values.len()` more elements.
let ptr = payloads.occupy_next_slots(env, builder, count);
```
- 注释声称会检查容量
- 实际代码中没有检查

---

#### 3. capacity 设置和调用链分析

**事实6**: capacity 在 cont.new 时初始化
- 源码位置：`crates/wasmtime/src/runtime/vm/stack_switching/stack/unix.rs:243-256`
```rust
let args_capacity = std::cmp::max(parameter_count, return_value_count);
args_ref.capacity = args_capacity;
```
- capacity = max(parameter_count, return_value_count)
- 基于 Wasm 函数类型信息，编译时确定

**事实7**: occupy_next_slots 的调用上下文
- 在 [vmcontref_store_payloads](cci:1://file:///Users/scc/code/researcher/wasmtime/crates/cranelift/src/func_environ/stack_switching/instructions.rs:842:0-907:1) 中被调用（第872行和887行）
- 调用时的 `count` 来自 `values.len()`
- `values.len()` 是编译时确定的参数个数
- 调用路径：cont.bind → translate_cont_bind → vmcontref_store_payloads → occupy_next_slots

**事实8**: arg_count 的可控性
- translate_cont_bind 中的 args 来自 Wasm 栈
- arg_count = src_types.len() - dst_arity（基于 Wasm 类型信息）
- 受 Wasm 类型系统约束，不是完全用户可控

---

### 二、无法从静态分析确认的推断

#### 对 fiber_start 的推断链条

**推断1**: array_call 失败时 params_and_returns 未初始化
- ❓ **无法确认**：源码未明确说明 failure 时的内存状态
- ❓ 需要动态分析或查阅文档确认

**推断2**: args.length 更新会让后续代码信任脏数据
- ❓ **无法确认**：需要追踪 args.length 的所有使用点
- ❓ 需要验证是否有代码依赖 length 字段进行内存访问

**推断3**: 这些数据用户可控
- ⚠️ **部分确认**：return_value_count 来自 Wasm 函数类型，受类型系统约束
- ❓ 但 trap 后的内存状态是否可控无法确认

#### 对 occupy_next_slots 的推断链条

**推断4**: capacity 不在调用前检查
- ❓ **无法确认**：虽然 occupy_next_slots 本身不检查，但调用者可能检查
- 需要验证 vmcontref_store_payloads 的调用者是否保证容量充足

**推断5**: 写越界能碰到敏感对象
- ❓ **无法确认**：需要分析具体的内存布局
- args 和 values 都在 continuation 栈上，但越界写入的目标对象未知

**推断6**: 可导致沙箱逃逸
- ❌ **无法确认**：从代码现象到沙箱逃逸缺少完整证明链
- 需要验证：越界写入 → 覆盖敏感数据 → 控制流劫持 → 逃逸

---

### 三、风险评估

#### 已确认的高风险模式

1. **忽略错误返回值**：fiber_start 忽略 array_call 的返回值
   - 开发者已标记为 TODO
   - 返回值有明确语义（trap recorded）

2. **注释与实现不符**：occupy_next_slots 注释声称检查容量，实际不检查
   - 可能是遗留注释或实现遗漏
   - 需要进一步确认设计意图

3. **无边界检查的长度更新**：occupy_next_slots 直接增加 length
   - 如果调用者未保证容量充足，可能导致逻辑错误

#### 需要进一步验证的风险

1. **fiber_start 的 trap 处理**：需要确认 trap 时 params_and_returns 的状态
2. **args.length 的使用**：需要追踪所有依赖 length 字段的代码
3. **capacity 保证机制**：需要确认是否有其他地方检查容量
4. **内存布局影响**：需要分析越界写入的具体影响范围

---

### 四、结论

**源码事实层面**：
- ✅ 报告中提到的两个代码模式确实存在于源码中
- ✅ fiber_start 确实忽略 array_call 返回值
- ✅ occupy_next_slots 确实没有检查 capacity

**漏洞结论层面**：
- ❌ 无法从静态分析确认这些模式必然导致可利用漏洞
- ❌ 从代码现象到沙箱逃逸缺少完整的证明链条
- ⚠️ 这些是值得人工审计的高风险代码模式

**工具价值**：
- ✅ 成功定位到 wasmtime 栈切换路径中的可疑代码模式
- ✅ 提供了高价值的人工审计入口
- ✅ 检测到了开发者已标记的问题（TODO 注释）

**已验证的事实**：
- fiber_start 确实忽略 array_call 返回值（开发者已标记 TODO）
- occupy_next_slots 确实缺少容量检查（注释与实现不符）
- capacity 在 cont.new 时基于类型信息初始化
- arg_count 受 Wasm 类型系统约束，非完全用户可控

**无法从静态分析确认的推断**：
- array_call 失败时 params_and_returns 的内存状态
- args.length 更新是否会让后续代码信任脏数据
- 越界写入是否能触碰敏感对象
- 是否可导致沙箱逃逸

**结论**：报告的源码事实层面可信，但漏洞结论层面过度推断。这些是高风险代码模式，需要人工复核和动态分析验证可利用性。