#!/usr/bin/env python3
"""
LocalLLM_Lab - 自动化基准测试脚本
运行多组实验并收集性能数据
"""

import os
import sys
import subprocess
import json
import time
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional

# 配置路径
PROJECT_ROOT = Path(__file__).parent
BUILD_DIR = PROJECT_ROOT / "build"
MODELS_DIR = PROJECT_ROOT / "models"
LOGS_DIR = PROJECT_ROOT / "logs"

# 可执行文件名（Windows 为 .exe，Linux/MacOS 无扩展名）
EXE_EXT = ".exe" if sys.platform == "win32" else ""
LLAMA_CLI = BUILD_DIR / f"llama-cli{EXE_EXT}"

# 测试提示词
TEST_PROMPT = "Write a short story about a robot learning to paint."

# 模型文件
MAIN_MODEL = MODELS_DIR / "Phi-3.5-mini-instruct-Q4_K_M.gguf"
DRAFT_MODEL = MODELS_DIR / "Qwen2-0.5B-Instruct-Q4_K_M.gguf"


def ensure_dirs():
    """确保必要的目录存在"""
    for dir_path in [BUILD_DIR, MODELS_DIR, LOGS_DIR]:
        dir_path.mkdir(parents=True, exist_ok=True)


def check_prerequisites() -> bool:
    """检查前置条件"""
    if not LLAMA_CLI.exists():
        print(f"❌ 错误: 找不到 {LLAMA_CLI}")
        print(f"   请先运行 build_llama.ps1 编译 llama.cpp")
        return False
    
    if not MAIN_MODEL.exists():
        print(f"❌ 错误: 找不到模型文件 {MAIN_MODEL}")
        print(f"   请先运行 download_models.ps1 下载模型")
        return False
    
    return True


def run_benchmark(
    name: str,
    threads: int = 4,
    kv_cache_type: Optional[str] = None,
    batch_size: int = 512,
    draft_model: Optional[Path] = None,
    n_predict: int = 128,
    n_prompt: int = 128
) -> Dict:
    """
    运行单次基准测试
    
    Args:
        name: 实验名称
        threads: CPU 线程数
        kv_cache_type: KV Cache 类型 (None=默认, "q8_0"=8-bit)
        batch_size: 批处理大小
        draft_model: Draft Model 路径（可选）
        n_predict: 生成 token 数量
        n_prompt: 提示词 token 数量
    """
    print(f"\n{'='*60}")
    print(f"🧪 运行实验: {name}")
    print(f"{'='*60}")
    
    # 构建命令
    cmd = [
        str(LLAMA_CLI),
        "-m", str(MAIN_MODEL),
        "-p", TEST_PROMPT,
        "-t", str(threads),
        "-n", str(n_predict),
        "--batch-size", str(batch_size),
        "--ctx-size", "2048",
        "--log-disable",
    ]
    
    # KV Cache 量化
    if kv_cache_type:
        cmd.extend(["-ctk", kv_cache_type, "-ctv", kv_cache_type])
    
    # Draft Model (投机采样)
    if draft_model and draft_model.exists():
        cmd.extend(["--draft", str(draft_model)])
    
    # 运行测试
    start_time = time.time()
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300,  # 5分钟超时
            encoding='utf-8',
            errors='ignore'
        )
        elapsed = time.time() - start_time
        
        # 解析输出
        output = result.stdout + result.stderr
        metrics = parse_output(output, elapsed, name)
        
        print(f"✅ 完成: {name}")
        print_metrics(metrics)
        
        return metrics
        
    except subprocess.TimeoutExpired:
        print(f"❌ 超时: {name}")
        return {"name": name, "error": "timeout"}
    except Exception as e:
        print(f"❌ 错误: {name} - {e}")
        return {"name": name, "error": str(e)}


def parse_output(output: str, elapsed: float, name: str) -> Dict:
    """解析 llama.cpp 输出，提取性能指标"""
    metrics = {
        "name": name,
        "elapsed_time": elapsed,
        "prompt_tokens": 0,
        "generated_tokens": 0,
        "prompt_tokens_per_sec": 0.0,
        "generated_tokens_per_sec": 0.0,
        "total_tokens_per_sec": 0.0,
    }
    
    # 尝试从输出中提取 token 统计
    lines = output.split('\n')
    for line in lines:
        line_lower = line.lower()
        
        # 查找 token 计数
        if "prompt" in line_lower and "token" in line_lower:
            # 尝试提取数字
            import re
            numbers = re.findall(r'\d+', line)
            if numbers:
                metrics["prompt_tokens"] = int(numbers[0])
        
        if "generated" in line_lower and "token" in line_lower:
            import re
            numbers = re.findall(r'\d+', line)
            if numbers:
                metrics["generated_tokens"] = int(numbers[0])
        
        # 查找 tokens/s
        if "tokens/s" in line_lower or "tokens per second" in line_lower:
            import re
            numbers = re.findall(r'\d+\.?\d*', line)
            if numbers:
                metrics["generated_tokens_per_sec"] = float(numbers[0])
    
    # 计算速率（如果未从输出中提取）
    if metrics["prompt_tokens"] > 0 and elapsed > 0:
        metrics["prompt_tokens_per_sec"] = metrics["prompt_tokens"] / elapsed
    
    if metrics["generated_tokens"] > 0 and elapsed > 0:
        if metrics["generated_tokens_per_sec"] == 0:
            metrics["generated_tokens_per_sec"] = metrics["generated_tokens"] / elapsed
    
    metrics["total_tokens_per_sec"] = (
        metrics["prompt_tokens_per_sec"] + metrics["generated_tokens_per_sec"]
    )
    
    return metrics


def print_metrics(metrics: Dict):
    """打印性能指标"""
    if "error" in metrics:
        print(f"   错误: {metrics['error']}")
        return
    
    print(f"   提示词 tokens: {metrics['prompt_tokens']}")
    print(f"   生成 tokens: {metrics['generated_tokens']}")
    print(f"   提示词速度: {metrics['prompt_tokens_per_sec']:.2f} t/s")
    print(f"   生成速度: {metrics['generated_tokens_per_sec']:.2f} t/s")
    print(f"   总耗时: {metrics['elapsed_time']:.2f} 秒")


def run_all_experiments() -> List[Dict]:
    """运行所有实验"""
    results = []
    
    # 基准线: 默认配置
    results.append(run_benchmark(
        name="Baseline (默认配置)",
        threads=4,
        kv_cache_type=None,
        batch_size=512
    ))
    
    # 实验 A: 线程缩放
    for threads in [4, 6, 8]:
        results.append(run_benchmark(
            name=f"实验A-{threads}线程",
            threads=threads,
            kv_cache_type=None,
            batch_size=512
        ))
    
    # 实验 B: KV Cache 量化
    results.append(run_benchmark(
        name="实验B-KV量化(q8_0)",
        threads=6,
        kv_cache_type="q8_0",
        batch_size=512
    ))
    
    # 实验 C: 批处理大小
    for batch_size in [256, 512, 1024]:
        results.append(run_benchmark(
            name=f"实验C-批处理{batch_size}",
            threads=6,
            kv_cache_type="q8_0",
            batch_size=batch_size
        ))
    
    # 实验 D: 投机采样 (如果 Draft Model 存在)
    if DRAFT_MODEL.exists():
        results.append(run_benchmark(
            name="实验D-投机采样",
            threads=6,
            kv_cache_type="q8_0",
            batch_size=512,
            draft_model=DRAFT_MODEL
        ))
    else:
        print(f"\n⚠️  跳过实验D: Draft Model 未找到 ({DRAFT_MODEL})")
    
    return results


def save_results(results: List[Dict]):
    """保存结果到 JSON 文件"""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = LOGS_DIR / f"benchmark_{timestamp}.json"
    
    with open(log_file, 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=2, ensure_ascii=False)
    
    print(f"\n📊 结果已保存到: {log_file}")
    
    # 同时生成 Markdown 报告
    md_file = LOGS_DIR / f"benchmark_{timestamp}.md"
    generate_markdown_report(results, md_file)
    print(f"📄 Markdown 报告已保存到: {md_file}")


def generate_markdown_report(results: List[Dict], output_file: Path):
    """生成 Markdown 格式的报告"""
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write("# LocalLLM_Lab 基准测试报告\n\n")
        f.write(f"生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        
        f.write("## 实验结果\n\n")
        f.write("| 实验名称 | 提示词速度 (t/s) | 生成速度 (t/s) | 总速度 (t/s) |\n")
        f.write("|---------|----------------|--------------|------------|\n")
        
        for r in results:
            if "error" not in r:
                f.write(f"| {r['name']} | "
                       f"{r['prompt_tokens_per_sec']:.2f} | "
                       f"{r['generated_tokens_per_sec']:.2f} | "
                       f"{r['total_tokens_per_sec']:.2f} |\n")
            else:
                f.write(f"| {r['name']} | ❌ {r['error']} | - | - |\n")
        
        f.write("\n## 详细数据\n\n")
        f.write("```json\n")
        f.write(json.dumps(results, indent=2, ensure_ascii=False))
        f.write("\n```\n")


def main():
    """主函数"""
    print("🚀 LocalLLM_Lab - 基准测试开始")
    print(f"   项目目录: {PROJECT_ROOT}")
    
    ensure_dirs()
    
    if not check_prerequisites():
        sys.exit(1)
    
    print(f"\n✅ 前置条件检查通过")
    print(f"   可执行文件: {LLAMA_CLI}")
    print(f"   主模型: {MAIN_MODEL}")
    print(f"   Draft 模型: {DRAFT_MODEL} ({'存在' if DRAFT_MODEL.exists() else '不存在'})")
    
    # 运行所有实验
    results = run_all_experiments()
    
    # 保存结果
    save_results(results)
    
    print("\n🎉 所有实验完成！")


if __name__ == "__main__":
    main()

