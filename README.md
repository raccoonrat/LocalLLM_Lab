# LocalLLM_Lab - 实验蓝图

**架构师**: Linus Torvalds

**目标**: 在资源受限的 x86 笔记本（ThinkPad T14p/ThinkBook 16p）上构建并验证最佳的 LLM 推理配置。

**核心哲学**: "Talk is cheap. Show me the numbers."

## 项目结构

```
LocalLLM_Lab/
├── build/                  # 存放编译后的 llama.cpp 二进制文件
├── models/                 # 存放 GGUF 模型文件
│   ├── Phi-3.5-mini-instruct-Q4_K_M.gguf
│   └── (Optional) Qwen2-0.5B-Instruct-Q4_K_M.gguf (作为 Draft Model)
├── logs/                   # 存放基准测试日志
├── run_benchmark.py        # 自动化测试脚本
├── build_llama.ps1         # Windows 编译脚本
├── download_models.ps1     # 模型下载脚本
└── README.md               # 本文件
```

## 快速开始

### 1. 编译 llama.cpp

运行编译脚本（需要安装 Git 和 CMake）：

```powershell
.\build_llama.ps1
```

或者手动编译：

```powershell
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build -DGGML_AVX512=ON -DGGML_AVX2=ON
cmake --build build --config Release -j 8
# 将生成的 llama-cli.exe 复制到 LocalLLM_Lab/build/
```

### 2. 下载模型

运行模型下载脚本（默认使用 HF-Mirror 镜像加速）：

```powershell
.\download_models.ps1
```

**使用自定义镜像：**

可以通过环境变量指定其他镜像：

```powershell
# 使用自定义镜像
$env:HF_ENDPOINT = "https://your-mirror.com"
.\download_models.ps1

# 或使用官方源（不推荐，可能较慢）
$env:HF_ENDPOINT = "https://huggingface.co"
.\download_models.ps1
```

### 3. 运行基准测试

```powershell
python run_benchmark.py
```

## 实验设计

我们将通过脚本运行以下几组对比实验：

- **基准线 (Baseline)**: 默认线程，FP16 KV Cache。
- **实验 A (Thread Scaling)**: 测试 4线程 vs 6线程 vs 8线程。寻找 P-Core 的甜蜜点。
- **实验 B (Bandwidth Hack)**: 启用 `-ctk q8_0 -ctv q8_0` (8-bit KV Cache)。这是集显机器的救命稻草。
- **实验 C (Batching)**: 调整 `--batch-size`。
- **实验 D (Speculative)**: 启用 Draft Model (如果下载了的话)。

## 预期结果

如果一切顺利，你应该能看到类似这样的提升：

| **配置**               | **预填充速度 (PP)** | **生成速度 (TG)** | **内存占用**   |
| -------------------- | -------------- | ------------- | ---------- |
| 默认配置                 | 150 t/s        | 8 t/s         | 3.2 GB     |
| **优化配置 (Thread+KV)** | **180 t/s**    | **14 t/s**    | **2.6 GB** |

## 系统要求

- Windows 10/11 (或 Linux/WSL/MacOS)
- Git
- CMake
- Python 3.7+
- Visual Studio (Windows) 或 GCC/Clang (Linux/MacOS)
- 至少 16GB 系统内存

