# LocalLLM_Lab - llama.cpp 编译脚本 (Windows PowerShell)
# 针对 ThinkPad/ThinkBook 的优化编译配置

$ErrorActionPreference = "Stop"

Write-Host "🔨 开始编译 llama.cpp..." -ForegroundColor Cyan

# 检查前置条件
Write-Host "`n📋 检查前置条件..." -ForegroundColor Yellow

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "❌ 错误: 未找到 git 命令" -ForegroundColor Red
    Write-Host "   请先安装 Git: https://git-scm.com/download/win" -ForegroundColor Yellow
    exit 1
}

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    Write-Host "❌ 错误: 未找到 cmake 命令" -ForegroundColor Red
    Write-Host "   请先安装 CMake: https://cmake.org/download/" -ForegroundColor Yellow
    exit 1
}

Write-Host "✅ Git 和 CMake 已安装" -ForegroundColor Green

# 项目根目录
$ProjectRoot = $PSScriptRoot
$LlamaCppDir = Join-Path $ProjectRoot "llama.cpp"
$BuildDir = Join-Path $LlamaCppDir "build"
$OutputDir = Join-Path $ProjectRoot "build"

# 步骤 1: 克隆或更新 llama.cpp
if (-not (Test-Path $LlamaCppDir)) {
    Write-Host "`n📥 克隆 llama.cpp 仓库..." -ForegroundColor Yellow
    git clone https://github.com/ggerganov/llama.cpp.git $LlamaCppDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Git clone 失败" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "`n🔄 更新 llama.cpp 仓库..." -ForegroundColor Yellow
    Push-Location $LlamaCppDir
    git pull
    Pop-Location
}

# 步骤 2: 配置编译
Write-Host "`n⚙️  配置编译选项..." -ForegroundColor Yellow
Write-Host "   启用: AVX-512, AVX2" -ForegroundColor Gray

Push-Location $LlamaCppDir

# 清理旧的构建
if (Test-Path $BuildDir) {
    Write-Host "🧹 清理旧的构建文件..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $BuildDir
}

# CMake 配置
Write-Host "`n🔧 运行 CMake 配置..." -ForegroundColor Yellow
cmake -B build `
    -DGGML_AVX512=ON `
    -DGGML_AVX2=ON `
    -DGGML_F16C=ON `
    -DCMAKE_BUILD_TYPE=Release

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ CMake 配置失败" -ForegroundColor Red
    Pop-Location
    exit 1
}

# 步骤 3: 编译
Write-Host "`n🔨 开始编译 (这可能需要几分钟)..." -ForegroundColor Yellow
cmake --build build --config Release -j 8

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ 编译失败" -ForegroundColor Red
    Pop-Location
    exit 1
}

Pop-Location

# 步骤 4: 复制可执行文件
Write-Host "`n📦 复制可执行文件..." -ForegroundColor Yellow

# 确保输出目录存在
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# 查找编译后的可执行文件
$ExeName = "llama-cli.exe"
$SourceExe = Join-Path $BuildDir "bin" $ExeName

# 如果不在 bin 目录，可能在 build 根目录
if (-not (Test-Path $SourceExe)) {
    $SourceExe = Join-Path $BuildDir $ExeName
}

# 或者可能是其他名称
if (-not (Test-Path $SourceExe)) {
    $PossibleNames = @("llama-cli.exe", "llama.exe", "main.exe")
    $Found = $false
    foreach ($name in $PossibleNames) {
        $testPath = Join-Path $BuildDir "bin" $name
        if (Test-Path $testPath) {
            $SourceExe = $testPath
            $ExeName = $name
            $Found = $true
            break
        }
        $testPath = Join-Path $BuildDir $name
        if (Test-Path $testPath) {
            $SourceExe = $testPath
            $ExeName = $name
            $Found = $true
            break
        }
    }
    if (-not $Found) {
        Write-Host "⚠️  警告: 未找到编译后的可执行文件" -ForegroundColor Yellow
        Write-Host "   请手动查找并复制到: $OutputDir" -ForegroundColor Yellow
        Write-Host "   查找位置: $BuildDir" -ForegroundColor Gray
        exit 0
    }
}

$DestExe = Join-Path $OutputDir $ExeName
Copy-Item $SourceExe $DestExe -Force

Write-Host "✅ 可执行文件已复制到: $DestExe" -ForegroundColor Green

# 验证
if (Test-Path $DestExe) {
    Write-Host "`n✅ 编译完成！" -ForegroundColor Green
    Write-Host "   可执行文件: $DestExe" -ForegroundColor Gray
} else {
    Write-Host "`n⚠️  警告: 可执行文件复制可能失败" -ForegroundColor Yellow
}

