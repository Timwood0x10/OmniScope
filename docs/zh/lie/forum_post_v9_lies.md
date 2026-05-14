# OmniScope v0.1.7：其实也没什么特别的

大家好，我是OmniScope的开发者。

今天发布v0.1.7，很多朋友问我们做了什么。我想了想，其实也没什么特别的，就是**把该做的事情做了而已**。

---

## 先说说现状吧

现在市面上的工具，我们也研究过。Clang Static Analyzer做了十几年，挺好的，C/C++分析得很深入。Rust Clippy是官方出品，代码风格检查很到位。Facebook Infer大厂背景，技术实力毋庸置疑。SonarQube商业成熟，很多企业都在用。

这些工具都很好，**只是有一个小问题**——

**它们都不做FFI分析。**

---

## FFI很难吗？

说实话，不难。就是麻烦。

你要理解不同语言的内存模型，要追踪跨语言边界的指针流向，要处理mangled name，要维护ownership语义... 

**都是些脏活累活。**

可能大厂觉得ROI不高吧，毕竟投入大、见效慢，还不如做几个 flashy 的功能吸引人。

但我们比较笨，**觉得这事总得有人做**。

---

## v0.1.7 做了什么？

### 测试通过率 340/340

也不是刻意追求的，就是写着写着，发现都过了。零失败，零跳过。

可能我们测试写得比较好吧。

### Precision 1.0

零误报。报的每个问题，都是真的问题。

这个其实挺难的，因为**宁可漏报也不能误报**——误报多了，用户就不信你了。我们花了很大精力在过滤噪声上，三层Zone分类，behavior-based分析...

但说出来好像也没什么，就是**细心**而已。

### 修复18个Bug

B1到B18，一个一个修过来的。有些挺低级的，比如字段名写错（"function" vs "func"），这种确实不应该。但发现了就修，没什么好说的。

---

## 技术细节（给感兴趣的朋友）

### 5层Pipeline架构

```
CallGraphPass → FFIBoundaryPass → DangerSurfacePass → PtrLifetimePass → PointerOwnershipPass
```

FFI边界专门有一层处理，不是补丁，是设计的时候就考虑进去。

**也不是多高级的想法**，就是觉得FFI不应该被当成二等公民。

### MemoryGraph关系图

- alloc/free边：内存生命周期
- alias边：别名分析
- call_arg/call_ret边：跨函数数据流

**不是看"调没调free"，是追踪"内存从哪来、到哪去"。**

这个思路挺自然的吧？不知道为什么没人做。

### word_boundary精准匹配

友商用 `strstr(func_name, "free")`，我们用的是完整词边界匹配。

**差别也不大**，就是误报率低一点而已。

---

## 一个例子

这段代码：

```rust
pub fn leaky() {
    let data = Box::new(42);
    let ptr = Box::into_raw(data);
    unsafe { c_consume(ptr); }
    // 忘了 Box::from_raw
}
```

| 工具 | 结果 |
|------|------|
| Clippy | 不报（unsafe里不管） |
| Infer | 不报（看不到所有权转移） |
| Clang SA | 不报（不支持Rust） |
| SonarQube | 不报（不支持FFI） |
| OmniScope | 报内存泄漏 |

**也不是说我们多厉害**，就是这个场景，我们覆盖了，它们没覆盖。

可能它们觉得这种代码写得少吧。但我们实际项目中，挺常见的。

---

## 代码质量

4轮代码审查，55+文件，82个问题定位。

8个Critical，27个High，全部记录。有些修了，有些在排期。

**也不是为了炫技**，就是觉得代码健康挺重要的。毕竟我们要跑在用户的项目里，不能出问题。

---

## 定价

免费。开源。

SonarQube几千刀一年，我们零元。

**也不是要搞价格战**，就是觉得安全工具不应该有门槛。特别是FFI这种高危场景，大家都能用得上。

---

## 怎么用？

```bash
git clone https://github.com/xxx/omniscope
cd omniscope && make release
./omniscope analyze --target ./your-project --output-format sarif
```

输出直接导入GitHub Code Scanning。

---

## 下一步

v0.1.7是Precision Release，零误报。

v0.1.8是Trust Release，目标Recall 0.5+，同时保持Precision 1.0。

**也不是多大的野心**，就是把这件事做好。

---

## 最后

我知道这个帖子看起来有点像拉踩，其实不是。每个工具都有自己的定位和取舍，我们只是**选择了一个没人愿意做的方向**，然后把它做出来而已。

如果其他工具以后也支持FFI分析了，那是好事，说明这个方向是对的。

但在那之前，**可能我们是唯一的选择**。

也不是骄傲，就是... **有点孤独吧**。

---

[GitHub]
[文档]
[Issue]

#OmniScope #FFI #静态分析 #Rust
