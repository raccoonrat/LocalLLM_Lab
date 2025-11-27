# LocalLLM_Lab - llama.cpp 编译脚本 (Windows PowerShell)
# 针对 ThinkPad/ThinkBook 的优化编译配置

$ErrorActionPreference = "Stop"

Write-Host "🔨 开始编译 llama.cpp..." -ForegroundColor Cyan

# 检查前置条件
Write-Host "`n📋 检查前置条件..." -ForegroundColor Yellow

# 检查 Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "❌ 错误: 未找到 git 命令" -ForegroundColor Red
    Write-Host "   请先安装 Git: https://git-scm.com/download/win" -ForegroundColor Yellow
    Write-Host "   或使用 winget: winget install Git.Git" -ForegroundColor Gray
    exit 1
}
Write-Host "✅ Git 已安装" -ForegroundColor Green

# 刷新 PATH（从注册表读取最新值）
Write-Host "🔄 刷新 PATH 环境变量..." -ForegroundColor Gray
$SystemPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = ($SystemPath, $UserPath, $env:Path) -join ';'

# 检查 CMake（包括常见安装位置）
$CmakePath = $null
if (Get-Command cmake -ErrorAction SilentlyContinue) {
    $CmakePath = "cmake"
    $cmakeVersion = & cmake --version | Select-Object -First 1
    Write-Host "✅ CMake 已安装 (在 PATH 中): $cmakeVersion" -ForegroundColor Green
} else {
    Write-Host "⚠️  CMake 不在 PATH 中，尝试查找安装位置..." -ForegroundColor Yellow
    
    # 检查常见安装位置
    $CommonCmakePaths = @(
        "${env:ProgramFiles}\CMake\bin\cmake.exe",
        "${env:ProgramFiles(x86)}\CMake\bin\cmake.exe"
    )
    
    foreach ($path in $CommonCmakePaths) {
        if (Test-Path $path) {
            $CmakePath = $path
            $cmakeVersion = & $path --version | Select-Object -First 1
            Write-Host "✅ 找到 CMake: $path" -ForegroundColor Green
            Write-Host "   版本: $cmakeVersion" -ForegroundColor Gray
            break
        }
    }
    
    # 检查 WinGet 安装位置（通配符搜索）
    if (-not $CmakePath) {
        $WinGetCmake = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter "cmake.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($WinGetCmake) {
            $CmakePath = $WinGetCmake.FullName
            $cmakeVersion = & $CmakePath --version | Select-Object -First 1
            Write-Host "✅ 找到 CMake (WinGet 安装): $CmakePath" -ForegroundColor Green
            Write-Host "   版本: $cmakeVersion" -ForegroundColor Gray
        }
    }
}

if (-not $CmakePath) {
    Write-Host "❌ 错误: 未找到 CMake" -ForegroundColor Red
    Write-Host "`n📦 安装选项:" -ForegroundColor Yellow
    Write-Host "   1. 使用 WinGet (推荐):" -ForegroundColor Cyan
    Write-Host "      winget install Kitware.CMake" -ForegroundColor White
    Write-Host "`n   2. 使用 Chocolatey:" -ForegroundColor Cyan
    Write-Host "      choco install cmake" -ForegroundColor White
    Write-Host "`n   3. 手动下载安装:" -ForegroundColor Cyan
    Write-Host "      https://cmake.org/download/" -ForegroundColor White
    Write-Host "`n💡 提示:" -ForegroundColor Yellow
    Write-Host "   - 安装后运行 .\refresh_path.ps1 刷新 PATH" -ForegroundColor Gray
    Write-Host "   - 或重新启动 PowerShell" -ForegroundColor Gray
    Write-Host "   - 本脚本会自动查找常见安装位置" -ForegroundColor Gray
    exit 1
}

# 检查 Visual Studio 或 Build Tools
$HasVisualStudio = $false
$VSPath = @(
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat",
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\Common7\Tools\VsDevCmd.bat",
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\Common7\Tools\VsDevCmd.bat",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Professional\Common7\Tools\VsDevCmd.bat"
)

foreach ($vs in $VSPath) {
    if (Test-Path $vs) {
        $HasVisualStudio = $true
        Write-Host "✅ 找到 Visual Studio" -ForegroundColor Green
        break
    }
}

if (-not $HasVisualStudio) {
    Write-Host "⚠️  警告: 未找到 Visual Studio" -ForegroundColor Yellow
    Write-Host "   建议安装 Visual Studio 2022 Community (免费)" -ForegroundColor Gray
    Write-Host "   下载: https://visualstudio.microsoft.com/downloads/" -ForegroundColor Gray
    Write-Host "   需要安装: Desktop development with C++" -ForegroundColor Gray
    Write-Host "   继续编译可能会失败..." -ForegroundColor Yellow
    $Continue = Read-Host "是否继续? (y/N)"
    if ($Continue -ne "y" -and $Continue -ne "Y") {
        exit 1
    }
}

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
& $CmakePath -B build `
    -DGGML_AVX512=ON `
    -DGGML_AVX2=ON `
    -DGGML_F16C=ON `
    -DCMAKE_BUILD_TYPE=Release

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ CMake 配置失败" -ForegroundColor Red
    Write-Host "   提示: 确保已安装 Visual Studio 或 Build Tools" -ForegroundColor Yellow
    Pop-Location
    exit 1
}

# 步骤 3: 编译
Write-Host "`n🔨 开始编译 (这可能需要几分钟)..." -ForegroundColor Yellow
& $CmakePath --build build --config Release -j 8

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

