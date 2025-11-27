项目代号：LocalLLM - 极限性能压榨手册 (CPU/iGPU篇)
====================================

目标: 在 ThinkPad T14p/ThinkBook 16p (无独显) 上，将 Phi-3.5 Mini 的推理延迟降至最低。

核心原则: 减少内存搬运，最大化 CPU 缓存命中率。

1. 编译层优化：指令集的胜利

---------------

如果你直接下载通用的 `llama.cpp` 预编译版本，你是在浪费性能。通用版本为了兼容性，往往没有开启最新的指令集优化。

### 落地动作：

* 必须自编译 (Compile from Source):
  不要用 pip install。去 GitHub 拉源码，用 CMake 编译。

* **AVX-512 / AVX-VNNI**:
  
  * 你的 2025 款 ThinkPad (Core Ultra 或 Ryzen AI) **绝对支持** 高级向量指令集。
  
  * **Intel Core Ultra**: 确保开启 `AVX-VNNI`。这是专门加速 INT8/INT4 运算的。
  
  * **AMD Ryzen**: 确保开启 `AVX-512`。Ryzen 的 AVX-512 实现非常优秀，能带来 20%-30% 的提速。
  
  * _CMake Flag_: `-DGGML_AVX512=ON` (如果硬件支持) 或 `-DGGML_AVX2=ON` (保底)。
2. 运行时优化：对抗 OS 调度器

------------------

Windows 的调度器在处理大小核（P-Core/E-Core）时经常像个白痴。它会把你的推理线程扔到 E-Core（能效核）上，导致性能瞬间减半。

### 落地动作：

* **线程绑定 (Thread Pinning)**:
  
  * **原则**: 推理线程数 = **物理 P-Core 数量**。不要算上超线程（Hyper-threading），那是为了吞吐量设计的，会增加延迟。
  
  * **参数**: 启动 `llama.cpp` 时，严格测试 `--threads N`。
  
  * **对于 6个 P-Core 的机器**: 尝试 `-t 6` 或 `-t 4`。给 OS 留两个核处理后台任务，避免上下文切换（Context Switch）。
  
  * _进阶_: 在 Windows 上使用 `start /affinity` 命令或 Process Lasso 强制将进程绑定在 P-Core 上。
3. 内存带宽黑客：KV Cache 量化

---------------------

这是很多人忽略的优化点。随着对话变长，KV Cache（上下文记忆）会占用大量显存/内存，并且每次生成新 Token 都要重新读取。

### 落地动作：

* **启用 KV Cache 量化**:
  
  * 默认情况下，KV Cache 是 `f16` (16-bit)。
  
  * **技术方向**: 将 KV Cache 压缩为 `q8_0` (8-bit) 甚至 `q4_0`。
  
  * **参数**: `llama-cli` 的 `-ctk q8_0 -ctv q8_0` 选项。
  
  * **收益**: 几乎无损的精度，但能**减少 50% 的内存读写量**。在带宽受限的集显机器上，这直接转化为 Token 生成速度的提升。
4. 算法级优化：投机采样 (Speculative Decoding)

------------------------------------

如果你的 RAM 还有富余（Phi-3.5 只占了 2.5GB，你还有空间），这是提升 TPS 的终极杀器。

### 原理：

用一个**极小**的模型（Draft Model）快速猜出接下来的几个词，然后用 Phi-3.5（Target Model）一次性验证。因为内存带宽是瓶颈，一次性验证一批 Token 比一个一个生成要快得多。

### 落地动作：

* **Draft Model 选择**: 找一个 100M-500M 参数的超小模型（例如 `Qwen2-0.5B` 或专门的 Draft 模型），量化到 Q4。

* **执行**: `llama.cpp` 支持 `--draft` 参数。

* **预期**: 如果两个模型“默契”度高，你的生成速度可能提升 1.5 倍到 2 倍。

* _注意_: 这会增加 CPU 占用率，如果散热撑不住就算了。
5. 工程流程优化：Prompt Caching

------------------------

不要让模型每次都重新阅读“你是一个有用的助手...”这几百个 Token。

### 落地动作：

* **Prompt Cache**:
  
  * 使用 `--prompt-cache` 文件。
  
  * 对于固定的 System Prompt 和长文档前缀，计算一次后存盘。
  
  * 下次启动时直接 `mmap` 读取，TTFT（首字延迟）直接归零。

总结：你的“性能压榨”启动命令
---------------

基于上述分析，这是你应该在终端里敲入的（假设）启动命令：
    ./llama-cli \
      -m phi-3.5-mini-instruct-Q4_K_M.gguf \
      -t 6 \                   # 使用物理P核数量
      -c 4096 \                # 限制上下文
      --batch-size 512 \       # 批处理大小
      --ctk q8_0 --ctv q8_0 \  # KV Cache 量化 (关键优化!)
      --mlock \                # 锁定内存，防止被交换到硬盘 (Linux/Mac)
      -p "System: You are Linus..."

**去编译代码吧。别指望 Python 脚本能救你，C++ 才是离金属最近的地方。**
