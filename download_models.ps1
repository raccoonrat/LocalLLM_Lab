# LocalLLM_Lab - 模型下载脚本 (Windows PowerShell)
# 下载所需的 GGUF 模型文件（支持镜像）

$ErrorActionPreference = "Stop"

Write-Host "📥 开始下载模型文件..." -ForegroundColor Cyan

# 镜像配置（默认使用 HF-Mirror）
# 可以通过环境变量 HF_ENDPOINT 覆盖，或修改下面的默认值
$HfMirror = $env:HF_ENDPOINT
if (-not $HfMirror) {
    # 默认使用 HF-Mirror（中国镜像）
    $HfMirror = "https://hf-mirror.com"
}

Write-Host "🌐 使用镜像: $HfMirror" -ForegroundColor Cyan
Write-Host "   (可通过环境变量 HF_ENDPOINT 修改)" -ForegroundColor Gray

# 设置环境变量（用于 huggingface-cli 和 Python）
$env:HF_ENDPOINT = $HfMirror

# 检查前置条件
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "❌ 错误: 未找到 python 命令" -ForegroundColor Red
    Write-Host "   请先安装 Python: https://www.python.org/downloads/" -ForegroundColor Yellow
    exit 1
}

# 项目目录
$ProjectRoot = $PSScriptRoot
$ModelsDir = Join-Path $ProjectRoot "models"

# 确保 models 目录存在
New-Item -ItemType Directory -Force -Path $ModelsDir | Out-Null

# 模型列表
$Models = @(
    @{
        Name = "Phi-3.5-mini-instruct-Q4_K_M.gguf"
        HuggingFaceRepo = "bartowski/Phi-3.5-mini-instruct-GGUF"
        FileName = "Phi-3.5-mini-instruct-Q4_K_M.gguf"
        Required = $true
    },
    @{
        Name = "Qwen2-0.5B-Instruct-Q4_K_M.gguf"
        HuggingFaceRepo = "Qwen/Qwen2.5-0.5B-Instruct-GGUF"
        FileName = "qwen2.5-0.5b-instruct-q4_k_m.gguf"
        Required = $false
    }
)

# 检查是否已安装 huggingface-cli
$HasHuggingFaceCli = $false
try {
    $null = Get-Command huggingface-cli -ErrorAction Stop
    $HasHuggingFaceCli = $true
} catch {
    Write-Host "`n⚠️  未找到 huggingface-cli，将使用 Python 脚本下载" -ForegroundColor Yellow
}

# 下载函数
function Download-Model {
    param(
        [hashtable]$ModelInfo
    )
    
    $ModelPath = Join-Path $ModelsDir $ModelInfo.Name
    
    # 检查是否已存在
    if (Test-Path $ModelPath) {
        Write-Host "✅ 已存在: $($ModelInfo.Name)" -ForegroundColor Green
        return $true
    }
    
    Write-Host "`n📥 下载: $($ModelInfo.Name)" -ForegroundColor Yellow
    Write-Host "   来源: $($ModelInfo.HuggingFaceRepo)" -ForegroundColor Gray
    
    if ($HasHuggingFaceCli) {
        # 使用 huggingface-cli（环境变量 HF_ENDPOINT 已设置）
        try {
            Write-Host "   使用 huggingface-cli 下载..." -ForegroundColor Gray
            # 注意: huggingface-cli 会自动读取 HF_ENDPOINT 环境变量
            huggingface-cli download $ModelInfo.HuggingFaceRepo `
                $ModelInfo.FileName `
                --local-dir $ModelsDir `
                --local-dir-use-symlinks False
            return $true
        } catch {
            Write-Host "❌ huggingface-cli 下载失败: $_" -ForegroundColor Red
            return $false
        }
    } else {
        # 使用 Python 脚本（支持镜像）
        $PythonScript = @"
import os
import sys
from pathlib import Path

# 设置镜像端点
hf_endpoint = r"$HfMirror"
os.environ["HF_ENDPOINT"] = hf_endpoint

try:
    from huggingface_hub import hf_hub_download
except ImportError:
    print("正在安装 huggingface_hub...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "huggingface_hub"])
    from huggingface_hub import hf_hub_download

repo_id = "$($ModelInfo.HuggingFaceRepo)"
filename = "$($ModelInfo.FileName)"
local_dir = r"$ModelsDir"

print(f"下载: {filename}")
print(f"仓库: {repo_id}")
print(f"镜像: {hf_endpoint}")

try:
    downloaded_path = hf_hub_download(
        repo_id=repo_id,
        filename=filename,
        local_dir=local_dir,
        local_dir_use_symlinks=False,
        endpoint=hf_endpoint
    )
    print(f"✅ 下载完成: {downloaded_path}")
except Exception as e:
    print(f"❌ 下载失败: {e}")
    sys.exit(1)
"@
        
        try {
            $PythonScript | python
            if ($LASTEXITCODE -eq 0) {
                return $true
            }
        } catch {
            Write-Host "❌ Python 下载失败: $_" -ForegroundColor Red
        }
        
        return $false
    }
}

# 下载所有模型
$SuccessCount = 0
$FailedModels = @()

foreach ($model in $Models) {
    if (Download-Model -ModelInfo $model) {
        $SuccessCount++
    } else {
        if ($model.Required) {
            $FailedModels += $model.Name
        } else {
            Write-Host "⚠️  可选模型下载失败，将跳过: $($model.Name)" -ForegroundColor Yellow
        }
    }
}

# 总结
Write-Host "`n" + "="*60 -ForegroundColor Cyan
Write-Host "📊 下载总结" -ForegroundColor Cyan
Write-Host "="*60 -ForegroundColor Cyan
Write-Host "成功: $SuccessCount / $($Models.Count)" -ForegroundColor $(if ($SuccessCount -eq $Models.Count) { "Green" } else { "Yellow" })

if ($FailedModels.Count -gt 0) {
    Write-Host "`n❌ 必需模型下载失败:" -ForegroundColor Red
    foreach ($model in $FailedModels) {
        Write-Host "   - $model" -ForegroundColor Red
    }
    Write-Host "`n请手动下载这些模型到: $ModelsDir" -ForegroundColor Yellow
    exit 1
}

Write-Host "`n✅ 所有模型下载完成！" -ForegroundColor Green
Write-Host "   模型目录: $ModelsDir" -ForegroundColor Gray

