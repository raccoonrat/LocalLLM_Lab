# LocalLLM_Lab - 刷新 PATH 环境变量脚本
# 解决 WinGet 安装的工具无法立即使用的问题

Write-Host "🔄 刷新 PATH 环境变量..." -ForegroundColor Cyan

# 从注册表读取系统 PATH
$SystemPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")

# 合并 PATH
$NewPath = ($SystemPath, $UserPath) -join ';'

# 更新当前会话的 PATH
$env:Path = $NewPath

Write-Host "✅ PATH 已刷新" -ForegroundColor Green

# 检查常见工具
Write-Host "`n📋 检查工具可用性:" -ForegroundColor Yellow

$Tools = @(
    @{ Name = "cmake"; Path = "cmake" },
    @{ Name = "git"; Path = "git" },
    @{ Name = "python"; Path = "python" }
)

foreach ($tool in $Tools) {
    if (Get-Command $tool.Path -ErrorAction SilentlyContinue) {
        $version = & $tool.Path --version 2>&1 | Select-Object -First 1
        Write-Host "  ✅ $($tool.Name): $version" -ForegroundColor Green
    } else {
        Write-Host "  ❌ $($tool.Name): 未找到" -ForegroundColor Red
    }
}

Write-Host "`n💡 提示: 如果工具仍然不可用，请重新启动 PowerShell" -ForegroundColor Yellow

