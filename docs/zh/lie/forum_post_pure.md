# OmniScope v0.1.7：我们为什么要做这件事？

大家好，我是OmniScope的产品经理，今天特别激动，想和大家聊聊v0.1.7。

## 故事要从一年前说起

那时候我们团队在用Rust写一个项目，需要调用C库。大家都知道，Rust的FFI是unsafe的，很容易出问题。

我们就想，找个工具检查一下呗。结果找了一圈——

**没有。真的没有。**

Clippy不管unsafe，Infer看不到跨语言边界，Clang SA不支持Rust... 

那天晚上，我们几个人坐在办公室里，特别沮丧。我就想，**这么重要的场景，为什么没人做？**

然后我说，**那我们自己做。**

---

## 这就是OmniScope的由来

我们做了一年，今天发布v0.1.7。我想用三个数字告诉大家，我们做到了什么：

### 第一个数字：340

**340/340 测试通过。**

零失败，零跳过。每一个测试用例，都是真刀真枪的场景。我们知道，工具稳定比什么都重要，如果工具本身有问题，怎么帮用户找问题？

### 第二个数字：1.0

**Precision 1.0。**

零误报。这个特别难，真的特别难。我们宁可漏报，也不能误报。因为误报一次，用户就不信你了。

我们做了三层Zone分类，behavior-based分析，word_boundary精准匹配... 就是为了**每一句话都负责任**。

### 第三个数字：0

**定价：0元。**

免费，开源。因为我们相信，**安全不应该是奢侈品**。每一个开发者，都应该用得上好的工具。

---

## 我们和友商有什么不同？

我不想说友商不好，每个产品都有自己的选择。但我想告诉大家，**我们的选择是什么**。

### 选择一：FFI是一等公民

我们把FFI分析放在架构的核心位置，专门有一层FFIBoundaryPass。不是补丁，不是后期加的，是**设计的时候就考虑进去**。

```
CallGraphPass → FFIBoundaryPass → DangerSurfacePass → PtrLifetimePass → PointerOwnershipPass
```

五层Pipeline，FFI在中间，前后都有支撑。

### 选择二：关系图驱动

别人用字符串匹配，我们用MemoryGraph。不是看"调没调free"，是追踪"内存从哪来、到哪去、经过谁的手"。

- alloc/free边：生命周期
- alias边：别名分析  
- call_arg/call_ret边：跨函数数据流

**这能一样吗？这完全不一样！**

### 选择三：死磕细节

4轮代码审查，55+文件，82个问题定位。8个Critical，27个High，一个一个过。

B1到B18，全部修复。有些特别低级，比如字段名写错（"function" vs "func"），但这种错误我们不允许。

---

## 给大家看一个真实的例子

这段代码，谁能发现问题？

```rust
pub fn leaky() {
    let data = Box::new(42);
    let ptr = Box::into_raw(data);
    unsafe { c_consume(ptr); }
    // 忘了 Box::from_raw
}
```

我们测了市面上所有工具：

| 工具 | 结果 |
|------|------|
| Clippy | ❌ 不报 |
| Infer | ❌ 不报 |
| Clang SA | ❌ 不报 |
| SonarQube | ❌ 不报 |
| **OmniScope** | ✅ **报内存泄漏** |

为什么我们能发现？

1. rustOwnershipHook识别into_raw
2. MemoryGraph追踪ptr流向
3. 发现没有匹配的from_raw
4. 报告内存泄漏

**这就是我们要做的事——让问题无处藏身。**

---

## 感动人心，价格厚道

SonarQube多少钱？几千刀一年。

我们多少钱？**免费。**

不是因为我们成本低，是因为我们**想和用户交朋友**。你用得好，帮我们传播，就是最大的支持。

---

## 怎么用？超简单

```bash
git clone https://github.com/xxx/omniscope
cd omniscope
make release
./omniscope analyze --target ./your-project --output-format sarif
```

输出直接导入GitHub Code Scanning，PR里直接看警告。

**开箱即用，一键集成。**

---

## 我们的目标

v0.1.7是Precision Release，零误报。

v0.1.8是Trust Release，目标Recall 0.5+，同时保持Precision 1.0。

我们的梦想是：**让全世界的开发者，写FFI代码的时候不再心慌。**

---

## 最后，我想说

做OmniScope这一年，特别累，但也特别开心。

因为我们在做一件**有价值的事**。

如果你也在用Rust写FFI，或者在做多语言项目，试试OmniScope。有问题随时找我们，我们**连夜改**。

谢谢大家！

---

[GitHub下载]
[完整文档]
[问题反馈]

#OmniScope #Rust #FFI #内存安全 #静态分析
