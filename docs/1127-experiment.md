项目代号：LocalLLM_Lab - 实验蓝图
========================

架构师: Linus Torvalds

目标: 在资源受限的 x86 笔记本（ThinkPad T14p/ThinkBook 16p）上构建并验证最佳的 LLM 推理配置。

核心哲学: "Talk is cheap. Show me the numbers."

1. 项目目录结构

---------

不要把文件乱扔在桌面上。创建一个干净的工作目录：
    LocalLLM_Lab/
    ├── build/                  # 存放编译后的 llama.cpp 二进制文件
    ├── models/                 # 存放 GGUF 模型文件
    │   ├── Phi-3.5-mini-instruct-Q4_K_M.gguf
    │   └── (Optional) Qwen2-0.5B-Instruct-Q4_K_M.gguf (作为 Draft Model)
    ├── logs/                   # 存放基准测试日志
    ├── run_benchmark.py        # 自动化测试脚本 (见下文)
    └── README.md               # 你现在的读物

2. 编译阶段 (The Build)

-------------------

这是最关键的一步。我们不能用默认设置。

### 步骤 A: 获取源码

你需要 `git` 和 `cmake`。
    git clone [https://github.com/ggerganov/llama.cpp](https://github.com/ggerganov/llama.cpp)
    cd llama.cpp

### 步骤 B: 针对 ThinkPad/ThinkBook 的编译配置

对于 Core Ultra (Intel) 或 Ryzen AI (AMD)，我们要开启 AVX-512 或 AVX-VNNI。

**构建命令 (Linux/WSL/MacOS):**
    mkdir build
    cd build
    cmake .. -DGGML_AVX512=ON -DGGML_AVX2=ON -DGGML_F16C=ON
    cmake --build . --config Release -j 8

**构建命令 (Windows PowerShell + Visual Studio):**
    cmake -B build -DGGML_AVX512=ON -DGGML_AVX2=ON
    cmake --build build --config Release -j 8

_注意：编译完成后，将生成的 `llama-cli` (或 `llama-cli.exe`) 复制到我们项目的 `LocalLLM_Lab/build/` 目录中。_

3. 模型获取 (The Payload)

---------------------

我们需要下载这两个特定的模型文件放入 `models/` 目录：

1. **主模型**: `Phi-3.5-mini-instruct-Q4_K_M.gguf`
   
   * _来源_: HuggingFace (bartowski 或 unsloth 仓库)
   
   * _理由_: 3.8B 参数，Q4 量化，内存占用 < 3GB，完美契合 16GB 共享内存。

2. **投机采样模型 (可选)**: `Qwen2.5-0.5B-Instruct-Q4_K_M.gguf`
   
   * _来源_: HuggingFace
   
   * _理由_: 极小，用于测试 Draft Model 是否能提升 TPS。

4. 实验设计 (The Experiments)

-------------------------

我们将通过脚本运行以下几组对比实验：

* **基准线 (Baseline)**: 默认线程，FP16 KV Cache。

* **实验 A (Thread Scaling)**: 测试 4线程 vs 6线程 vs 8线程。寻找 P-Core 的甜蜜点。

* **实验 B (Bandwidth Hack)**: 启用 `-ctk q8_0 -ctv q8_0` (8-bit KV Cache)。这是集显机器的救命稻草。

* **实验 C (Batching)**: 调整 `--batch-size`。

* **实验 D (Speculative)**: 启用 Draft Model (如果下载了的话)。
5. 预期结果

-------

如果一切顺利，你应该能看到类似这样的提升：

| **配置**               | **预填充速度 (PP)** | **生成速度 (TG)** | **内存占用**   |
| -------------------- | -------------- | ------------- | ---------- |
| 默认配置                 | 150 t/s        | 8 t/s         | 3.2 GB     |
| **优化配置 (Thread+KV)** | **180 t/s**    | **14 t/s**    | **2.6 GB** |

去执行吧。编译完二进制文件后，运行 Python 脚本。
