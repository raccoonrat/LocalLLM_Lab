# LocalLLM_Lab - 依赖安装脚本 (Windows PowerShell)
# 自动安装编译所需的工具

$ErrorActionPreference = "Stop"

Write-Host "📦 LocalLLM_Lab 依赖安装脚本" -ForegroundColor Cyan
Write-Host "="*60 -ForegroundColor Cyan

# 检查管理员权限（某些安装可能需要）
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "`n⚠️  提示: 某些安装可能需要管理员权限" -ForegroundColor Yellow
    Write-Host "   如果安装失败，请以管理员身份运行 PowerShell" -ForegroundColor Gray
}

# 检查并安装工具
$Tools = @()

# 1. Git
Write-Host "`n📋 检查 Git..." -ForegroundColor Yellow
if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitVersion = git --version
    Write-Host "✅ Git 已安装: $gitVersion" -ForegroundColor Green
} else {
    Write-Host "❌ Git 未安装" -ForegroundColor Red
    $Tools += @{
        Name = "Git"
        WinGetId = "Git.Git"
        DownloadUrl = "https://git-scm.com/download/win"
        Required = $true
    }
}

# 2. CMake
Write-Host "`n📋 检查 CMake..." -ForegroundColor Yellow
$CmakeInstalled = $false
if (Get-Command cmake -ErrorAction SilentlyContinue) {
    $cmakeVersion = cmake --version | Select-Object -First 1
    Write-Host "✅ CMake 已安装: $cmakeVersion" -ForegroundColor Green
    $CmakeInstalled = $true
} else {
    # 检查常见安装位置
    $CommonCmakePaths = @(
        "${env:ProgramFiles}\CMake\bin\cmake.exe",
        "${env:ProgramFiles(x86)}\CMake\bin\cmake.exe"
    )
    foreach ($path in $CommonCmakePaths) {
        if (Test-Path $path) {
            Write-Host "✅ CMake 已安装 (但不在 PATH): $path" -ForegroundColor Green
            Write-Host "   建议将 CMake 添加到系统 PATH" -ForegroundColor Yellow
            $CmakeInstalled = $true
            break
        }
    }
}

if (-not $CmakeInstalled) {
    Write-Host "❌ CMake 未安装" -ForegroundColor Red
    $Tools += @{
        Name = "CMake"
        WinGetId = "Kitware.CMake"
        DownloadUrl = "https://cmake.org/download/"
        Required = $true
    }
}

# 3. Visual Studio
Write-Host "`n📋 检查 Visual Studio..." -ForegroundColor Yellow
$VSInstalled = $false
$VSPaths = @(
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community",
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional",
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community"
)

foreach ($vsPath in $VSPaths) {
    if (Test-Path $vsPath) {
        Write-Host "✅ Visual Studio 已安装: $vsPath" -ForegroundColor Green
        $VSInstalled = $true
        break
    }
}

if (-not $VSInstalled) {
    Write-Host "❌ Visual Studio 未安装" -ForegroundColor Red
    $Tools += @{
        Name = "Visual Studio 2022 Community"
        WinGetId = "Microsoft.VisualStudio.2022.Community"
        DownloadUrl = "https://visualstudio.microsoft.com/downloads/"
        Required = $true
        Note = "需要安装 'Desktop development with C++' 工作负载"
    }
}

# 4. Python (用于下载模型)
Write-Host "`n📋 检查 Python..." -ForegroundColor Yellow
if (Get-Command python -ErrorAction SilentlyContinue) {
    $pythonVersion = python --version
    Write-Host "✅ Python 已安装: $pythonVersion" -ForegroundColor Green
} else {
    Write-Host "⚠️  Python 未安装 (可选，用于下载模型)" -ForegroundColor Yellow
    $Tools += @{
        Name = "Python"
        WinGetId = "Python.Python.3.12"
        DownloadUrl = "https://www.python.org/downloads/"
        Required = $false
    }
}

# 总结
Write-Host "`n" + "="*60 -ForegroundColor Cyan
Write-Host "📊 检查结果" -ForegroundColor Cyan
Write-Host "="*60 -ForegroundColor Cyan

if ($Tools.Count -eq 0) {
    Write-Host "`n✅ 所有必需工具已安装！" -ForegroundColor Green
    Write-Host "   可以运行 .\build_llama.ps1 开始编译" -ForegroundColor Gray
    exit 0
}

Write-Host "`n需要安装以下工具:" -ForegroundColor Yellow
foreach ($tool in $Tools) {
    $status = if ($tool.Required) { "必需" } else { "可选" }
    Write-Host "  - $($tool.Name) ($status)" -ForegroundColor $(if ($tool.Required) { "Red" } else { "Yellow" })
    if ($tool.Note) {
        Write-Host "    注意: $($tool.Note)" -ForegroundColor Gray
    }
}

# 检查 WinGet
Write-Host "`n📦 检查包管理器..." -ForegroundColor Yellow
$HasWinGet = Get-Command winget -ErrorAction SilentlyContinue
$HasChoco = Get-Command choco -ErrorAction SilentlyContinue

if ($HasWinGet) {
    Write-Host "✅ WinGet 可用" -ForegroundColor Green
    $PackageManager = "winget"
} elseif ($HasChoco) {
    Write-Host "✅ Chocolatey 可用" -ForegroundColor Green
    $PackageManager = "choco"
} else {
    Write-Host "❌ 未找到包管理器 (WinGet 或 Chocolatey)" -ForegroundColor Red
    Write-Host "`n📥 手动安装链接:" -ForegroundColor Yellow
    foreach ($tool in $Tools) {
        Write-Host "  $($tool.Name): $($tool.DownloadUrl)" -ForegroundColor Cyan
    }
    exit 1
}

# 询问是否自动安装
Write-Host "`n❓ 是否使用 $PackageManager 自动安装? (Y/n)" -ForegroundColor Yellow
$Response = Read-Host

if ($Response -eq "n" -or $Response -eq "N") {
    Write-Host "`n📥 手动安装链接:" -ForegroundColor Yellow
    foreach ($tool in $Tools) {
        Write-Host "  $($tool.Name): $($tool.DownloadUrl)" -ForegroundColor Cyan
    }
    exit 0
}

# 自动安装
Write-Host "`n🚀 开始自动安装..." -ForegroundColor Cyan

foreach ($tool in $Tools) {
    Write-Host "`n📦 安装 $($tool.Name)..." -ForegroundColor Yellow
    
    if ($PackageManager -eq "winget") {
        try {
            if ($tool.WinGetId) {
                winget install $tool.WinGetId --accept-package-agreements --accept-source-agreements
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ $($tool.Name) 安装成功" -ForegroundColor Green
                } else {
                    Write-Host "❌ $($tool.Name) 安装失败" -ForegroundColor Red
                    if ($tool.Required) {
                        Write-Host "   请手动安装: $($tool.DownloadUrl)" -ForegroundColor Yellow
                    }
                }
            }
        } catch {
            Write-Host "❌ 安装失败: $_" -ForegroundColor Red
        }
    } elseif ($PackageManager -eq "choco") {
        try {
            $chocoId = switch ($tool.WinGetId) {
                "Git.Git" { "git" }
                "Kitware.CMake" { "cmake" }
                "Python.Python.3.12" { "python" }
                default { $null }
            }
            if ($chocoId) {
                choco install $chocoId -y
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ $($tool.Name) 安装成功" -ForegroundColor Green
                } else {
                    Write-Host "❌ $($tool.Name) 安装失败" -ForegroundColor Red
                }
            }
        } catch {
            Write-Host "❌ 安装失败: $_" -ForegroundColor Red
        }
    }
}

Write-Host "`n" + "="*60 -ForegroundColor Cyan
Write-Host "✅ 安装完成！" -ForegroundColor Green
Write-Host "`n⚠️  重要提示:" -ForegroundColor Yellow
Write-Host "   1. 如果安装了新工具，请重新启动 PowerShell 以确保 PATH 生效" -ForegroundColor Gray
Write-Host "   2. Visual Studio 安装后需要重启计算机" -ForegroundColor Gray
Write-Host "   3. 然后运行 .\build_llama.ps1 开始编译" -ForegroundColor Gray

