<#
.SYNOPSIS
    ClawSysAdmin - 浏览器缓存清理模块
.DESCRIPTION
    清理 Edge、Chrome、Firefox 浏览器缓存
.AUTHOR
    夜爪数字公司
.VERSION
    0.1.0
#>

# 设置编码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 辅助函数：格式化字节
function Format-Bytes {
    param([long]$Bytes)
    $sizes = @("B", "KB", "MB", "GB", "TB")
    $order = 0
    $value = $Bytes
    while ($value -ge 1024 -and $order -lt $sizes.Count - 1) {
        $value = $value / 1024
        $order++
    }
    return "{0:N2} {1}" -f $value, $sizes[$order]
}

# 辅助函数：清理目录
function Clear-BrowserCache {
    param(
        [string]$Path,
        [string]$BrowserName
    )
    
    if (!(Test-Path $Path)) {
        return @{ Success = $false; Size = 0; Count = 0; Message = "路径不存在" }
    }
    
    try {
        $totalSize = 0
        $fileCount = 0
        
        # 获取缓存文件
        $cacheFiles = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue
        
        foreach ($file in $cacheFiles) {
            try {
                $size = $file.Length
                Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
                $totalSize += $size
                $fileCount++
            } catch {}
        }
        
        return @{
            Success = $true
            Size = $totalSize
            Count = $fileCount
            Message = "成功清理"
        }
    } catch {
        return @{
            Success = $false
            Size = 0
            Count = 0
            Message = $_.Exception.Message
        }
    }
}

# ==================== Edge 浏览器 ====================
function Clear-EdgeCache {
    $cachePaths = @(
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache"
    )
    
    $totalSize = 0
    $totalCount = 0
    
    foreach ($path in $cachePaths) {
        $result = Clear-BrowserCache -Path $path -BrowserName "Edge"
        $totalSize += $result.Size
        $totalCount += $result.Count
    }
    
    return @{ Size = $totalSize; Count = $totalCount }
}

# ==================== Chrome 浏览器 ====================
function Clear-ChromeCache {
    $cachePaths = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache"
    )
    
    $totalSize = 0
    $totalCount = 0
    
    foreach ($path in $cachePaths) {
        $result = Clear-BrowserCache -Path $path -BrowserName "Chrome"
        $totalSize += $result.Size
        $totalCount += $result.Count
    }
    
    return @{ Size = $totalSize; Count = $totalCount }
}

# ==================== Firefox 浏览器 ====================
function Clear-FirefoxCache {
    $firefoxPath = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    
    if (!(Test-Path $firefoxPath)) {
        return @{ Size = 0; Count = 0 }
    }
    
    $profiles = Get-ChildItem -Path $firefoxPath -Directory -ErrorAction SilentlyContinue
    $totalSize = 0
    $totalCount = 0
    
    foreach ($profile in $profiles) {
        $cachePath = "$($profile.FullName)\cache2"
        $result = Clear-BrowserCache -Path $cachePath -BrowserName "Firefox"
        $totalSize += $result.Size
        $totalCount += $result.Count
    }
    
    return @{ Size = $totalSize; Count = $totalCount }
}

# ==================== 主函数 ====================
function Start-BrowserCacheCleanup {
    Write-Host "
╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           🐾 ClawSysAdmin - 浏览器缓存清理                  ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    # 检查浏览器
    $edgeInstalled = Test-Path "$env:LOCALAPPDATA\Microsoft\Edge"
    $chromeInstalled = Test-Path "$env:LOCALAPPDATA\Google\Chrome"
    $firefoxInstalled = Test-Path "$env:LOCALAPPDATA\Mozilla\Firefox"
    
    Write-Host "【检测到浏览器】" -ForegroundColor Yellow
    if ($edgeInstalled) { Write-Host "  ✅ Microsoft Edge" -ForegroundColor Green }
    if ($chromeInstalled) { Write-Host "  ✅ Google Chrome" -ForegroundColor Green }
    if ($firefoxInstalled) { Write-Host "  ✅ Mozilla Firefox" -ForegroundColor Green }
    if (!$edgeInstalled -and !$chromeInstalled -and !$firefoxInstalled) {
        Write-Host "  ⚠️ 未检测到支持的浏览器" -ForegroundColor Yellow
        return
    }
    Write-Host ""
    
    # 开始清理
    $results = @()
    
    if ($edgeInstalled) {
        Write-Host "正在清理 Microsoft Edge 缓存..." -ForegroundColor Gray
        $result = Clear-EdgeCache
        $results += @{ Browser = "Microsoft Edge"; Result = $result }
        Write-Host "  清理完成: $(Format-Bytes -Bytes $result.Size)" -ForegroundColor Green
    }
    
    if ($chromeInstalled) {
        Write-Host "正在清理 Google Chrome 缓存..." -ForegroundColor Gray
        $result = Clear-ChromeCache
        $results += @{ Browser = "Google Chrome"; Result = $result }
        Write-Host "  清理完成: $(Format-Bytes -Bytes $result.Size)" -ForegroundColor Green
    }
    
    if ($firefoxInstalled) {
        Write-Host "正在清理 Mozilla Firefox 缓存..." -ForegroundColor Gray
        $result = Clear-FirefoxCache
        $results += @{ Browser = "Mozilla Firefox"; Result = $result }
        Write-Host "  清理完成: $(Format-Bytes -Bytes $result.Size)" -ForegroundColor Green
    }
    
    # 汇总
    $totalSize = 0
    $totalCount = 0
    foreach ($r in $results) {
        $totalSize += $r.Result.Size
        $totalCount += $r.Result.Count
    }
    
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                      📊 清理汇总                             ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    
    foreach ($r in $results) {
        Write-Host "  $($r.Browser): $(Format-Bytes -Bytes $r.Result.Size) ($($r.Result.Count) 个文件)" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "  总计释放: $(Format-Bytes -Bytes $totalSize)" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "💡 提示:" -ForegroundColor Gray
    Write-Host "  定期清理浏览器缓存可以提高浏览器性能" -ForegroundColor Gray
    Write-Host ""
}

# 执行主函数
Start-BrowserCacheCleanup
